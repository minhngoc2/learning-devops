package events

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type localPublisher struct {
	baseURL string
	client  *http.Client
}

// NewLocalPublisher posts events to cmd/localbus at baseURL (POST /publish).
func NewLocalPublisher(baseURL string) Publisher {
	return &localPublisher{baseURL: strings.TrimRight(baseURL, "/"), client: &http.Client{Timeout: 5 * time.Second}}
}

func (p *localPublisher) Publish(ctx context.Context, e Event) error {
	body, err := json.Marshal(e)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.baseURL+"/publish", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		return fmt.Errorf("localbus publish: %w", err)
	}
	resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("localbus publish: status %d", resp.StatusCode)
	}
	return nil
}

type localConsumer struct {
	baseURL  string
	consumer string
	client   *http.Client
}

// NewLocalConsumer long-polls cmd/localbus (GET /poll/{consumer}) and acks handled events
// (POST /ack/{consumer}/{eventId}). Unacked events are redelivered by the bus.
func NewLocalConsumer(baseURL, consumer string) Consumer {
	return &localConsumer{
		baseURL:  strings.TrimRight(baseURL, "/"),
		consumer: consumer,
		client:   &http.Client{Timeout: 30 * time.Second}, // > the bus's 20 s long poll
	}
}

func (c *localConsumer) Run(ctx context.Context, h Handler) error {
	log := slog.Default()
	for ctx.Err() == nil {
		batch, err := c.poll(ctx)
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			log.Error("localbus poll", "consumer", c.consumer, "err", err)
			select {
			case <-ctx.Done():
			case <-time.After(2 * time.Second):
			}
			continue
		}
		for _, e := range batch {
			if err := h(ctx, e); err != nil {
				log.Error("handle event; leaving it for redelivery", "event_id", e.EventID, "event_type", e.EventType, "err", err)
				continue
			}
			if err := c.ack(context.WithoutCancel(ctx), e.EventID); err != nil {
				log.Error("localbus ack", "event_id", e.EventID, "err", err)
			}
		}
	}
	return nil
}

func (c *localConsumer) poll(ctx context.Context) ([]Event, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/poll/"+url.PathEscape(c.consumer), nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", resp.StatusCode)
	}
	var batch []Event
	if err := json.NewDecoder(resp.Body).Decode(&batch); err != nil {
		return nil, err
	}
	return batch, nil
}

func (c *localConsumer) ack(ctx context.Context, eventID string) error {
	u := c.baseURL + "/ack/" + url.PathEscape(c.consumer) + "/" + url.PathEscape(eventID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, nil)
	if err != nil {
		return err
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("status %d", resp.StatusCode)
	}
	return nil
}
