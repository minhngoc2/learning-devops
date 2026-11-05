package cart

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

// dynamoAPI is the part of *dynamodb.Client the store uses. The task role allows exactly these four
// actions (no Query/Scan).
type dynamoAPI interface {
	GetItem(ctx context.Context, in *dynamodb.GetItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error)
	PutItem(ctx context.Context, in *dynamodb.PutItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error)
	UpdateItem(ctx context.Context, in *dynamodb.UpdateItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error)
	DeleteItem(ctx context.Context, in *dynamodb.DeleteItemInput, optFns ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error)
}

// record is the DynamoDB item: key customer_sub, items (map product id → quantity), updated_at (RFC 3339)
// and ttl (epoch seconds; the table's TTL deletes carts idle for ttlDays).
type record struct {
	CustomerSub string         `dynamodbav:"customer_sub"`
	Items       map[string]int `dynamodbav:"items"`
	UpdatedAt   string         `dynamodbav:"updated_at"`
	TTL         int64          `dynamodbav:"ttl"`
}

type dynamoStore struct {
	api     dynamoAPI
	table   string
	ttlDays int
	now     func() time.Time
}

// NewDynamoStore stores one item per customer in table; every write pushes the expiry ttlDays out.
func NewDynamoStore(client *dynamodb.Client, table string, ttlDays int) Store {
	return &dynamoStore{api: client, table: table, ttlDays: ttlDays, now: time.Now}
}

func (s *dynamoStore) key(sub string) map[string]types.AttributeValue {
	return map[string]types.AttributeValue{"customer_sub": &types.AttributeValueMemberS{Value: sub}}
}

func (s *dynamoStore) Get(ctx context.Context, sub string) (Cart, error) {
	out, err := s.api.GetItem(ctx, &dynamodb.GetItemInput{
		TableName:      aws.String(s.table),
		Key:            s.key(sub),
		ConsistentRead: aws.Bool(true),
	})
	if err != nil {
		return Cart{}, fmt.Errorf("dynamodb get cart: %w", err)
	}
	return s.decode(sub, out.Item)
}

// PutItem updates one map entry in place so concurrent edits to other lines are not lost. The update is
// conditional on a live (unexpired) cart; otherwise the first write replaces the item with a fresh cart.
func (s *dynamoStore) PutItem(ctx context.Context, sub, productID string, qty int) (Cart, error) {
	now := s.now().UTC().Truncate(time.Second) // stored as RFC 3339 seconds; return the same value
	values := map[string]types.AttributeValue{
		":now":   &types.AttributeValueMemberS{Value: now.Format(time.RFC3339)},
		":ttl":   &types.AttributeValueMemberN{Value: strconv.FormatInt(s.expiry(now), 10)},
		":epoch": &types.AttributeValueMemberN{Value: strconv.FormatInt(now.Unix(), 10)},
	}
	update := "SET updated_at = :now, #ttl = :ttl REMOVE #items.#pid"
	condition := "attribute_exists(#items) AND #ttl >= :epoch"
	if qty > 0 {
		values[":qty"] = &types.AttributeValueMemberN{Value: strconv.Itoa(qty)}
		values[":max"] = &types.AttributeValueMemberN{Value: strconv.Itoa(MaxLines)}
		update = "SET #items.#pid = :qty, updated_at = :now, #ttl = :ttl"
		// A new key may only be added below MaxLines lines; an existing line can always change.
		condition += " AND (attribute_exists(#items.#pid) OR size(#items) < :max)"
	}

	for range 3 { // retries only when a concurrent first write races us
		out, err := s.api.UpdateItem(ctx, &dynamodb.UpdateItemInput{
			TableName:                           aws.String(s.table),
			Key:                                 s.key(sub),
			UpdateExpression:                    aws.String(update),
			ConditionExpression:                 aws.String(condition),
			ExpressionAttributeNames:            map[string]string{"#items": "items", "#pid": productID, "#ttl": "ttl"},
			ExpressionAttributeValues:           values,
			ReturnValues:                        types.ReturnValueAllNew,
			ReturnValuesOnConditionCheckFailure: types.ReturnValuesOnConditionCheckFailureAllOld,
		})
		if err == nil {
			return s.decode(sub, out.Attributes)
		}
		if !isConditionFailed(err) {
			return Cart{}, fmt.Errorf("dynamodb update cart: %w", err)
		}
		if qty == 0 { // no cart, so nothing to remove
			return newCart(sub, nil, time.Time{}), nil
		}
		// The condition also fails on a live cart that is full: that is the caller's error, not a missing cart.
		if old, err := s.decode(sub, conditionFailedItem(err)); err == nil && len(old.Items) >= MaxLines &&
			!slices.ContainsFunc(old.Items, func(it Item) bool { return it.ProductID == productID }) {
			return Cart{}, ErrCartFull
		}

		rec := record{CustomerSub: sub, Items: map[string]int{productID: qty}, UpdatedAt: now.Format(time.RFC3339), TTL: s.expiry(now)}
		item, err := attributevalue.MarshalMap(rec)
		if err != nil {
			return Cart{}, err
		}
		_, err = s.api.PutItem(ctx, &dynamodb.PutItemInput{
			TableName:                 aws.String(s.table),
			Item:                      item,
			ConditionExpression:       aws.String("attribute_not_exists(customer_sub) OR #ttl < :epoch"),
			ExpressionAttributeNames:  map[string]string{"#ttl": "ttl"},
			ExpressionAttributeValues: map[string]types.AttributeValue{":epoch": values[":epoch"]},
		})
		if err == nil {
			return newCart(sub, rec.Items, now), nil
		}
		if !isConditionFailed(err) {
			return Cart{}, fmt.Errorf("dynamodb create cart: %w", err)
		}
	}
	return Cart{}, errors.New("dynamodb put cart item: gave up after concurrent writes")
}

func (s *dynamoStore) Clear(ctx context.Context, sub string) error {
	if _, err := s.api.DeleteItem(ctx, &dynamodb.DeleteItemInput{TableName: aws.String(s.table), Key: s.key(sub)}); err != nil {
		return fmt.Errorf("dynamodb delete cart: %w", err)
	}
	return nil
}

func (s *dynamoStore) expiry(now time.Time) int64 {
	return now.Add(time.Duration(s.ttlDays) * 24 * time.Hour).Unix()
}

// decode treats a missing item, or one past its ttl that DynamoDB has not deleted yet, as an empty cart.
func (s *dynamoStore) decode(sub string, item map[string]types.AttributeValue) (Cart, error) {
	if len(item) == 0 {
		return newCart(sub, nil, time.Time{}), nil
	}
	var rec record
	if err := attributevalue.UnmarshalMap(item, &rec); err != nil {
		return Cart{}, fmt.Errorf("dynamodb decode cart: %w", err)
	}
	if rec.TTL != 0 && rec.TTL < s.now().Unix() {
		return newCart(sub, nil, time.Time{}), nil
	}
	updatedAt, _ := time.Parse(time.RFC3339, rec.UpdatedAt)
	return newCart(sub, rec.Items, updatedAt), nil
}

func isConditionFailed(err error) bool {
	var ccf *types.ConditionalCheckFailedException
	return errors.As(err, &ccf)
}

// conditionFailedItem is the item as it was when the condition failed (ReturnValuesOnConditionCheckFailure ALL_OLD).
func conditionFailedItem(err error) map[string]types.AttributeValue {
	var ccf *types.ConditionalCheckFailedException
	if errors.As(err, &ccf) {
		return ccf.Item
	}
	return nil
}
