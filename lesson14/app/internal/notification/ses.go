package notification

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sesv2"
	"github.com/aws/aws-sdk-go-v2/service/sesv2/types"
)

// sesAPI is the part of *sesv2.Client the sender uses; tests pass a fake.
type sesAPI interface {
	SendEmail(ctx context.Context, in *sesv2.SendEmailInput, optFns ...func(*sesv2.Options)) (*sesv2.SendEmailOutput, error)
}

type sesSender struct {
	api  sesAPI
	from string
}

// NewSESSender sends through SES v2 from the verified identity from (NOTIFY_FROM). In the SES sandbox the
// recipient must be verified too.
func NewSESSender(client *sesv2.Client, from string) Sender {
	return &sesSender{api: client, from: from}
}

func (s *sesSender) Send(ctx context.Context, to, subject, body string) error {
	_, err := s.api.SendEmail(ctx, &sesv2.SendEmailInput{
		FromEmailAddress: aws.String(s.from),
		Destination:      &types.Destination{ToAddresses: []string{to}},
		Content: &types.EmailContent{Simple: &types.Message{
			Subject: &types.Content{Data: aws.String(subject), Charset: aws.String("UTF-8")},
			Body:    &types.Body{Text: &types.Content{Data: aws.String(body), Charset: aws.String("UTF-8")}},
		}},
	})
	if err != nil {
		return fmt.Errorf("ses send email: %w", err)
	}
	return nil
}
