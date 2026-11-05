package cart

import (
	"context"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

// fakeDynamo keeps one record per customer and evaluates the store's two condition expressions the way
// DynamoDB would. It records the calls in order.
type fakeDynamo struct {
	t     *testing.T
	items map[string]record
	calls []string
}

func newFakeDynamo(t *testing.T) *fakeDynamo { return &fakeDynamo{t: t, items: map[string]record{}} }

func ccf() error { return &types.ConditionalCheckFailedException{Message: aws.String("The conditional request failed")} }

func subOf(key map[string]types.AttributeValue) string {
	return key["customer_sub"].(*types.AttributeValueMemberS).Value
}

func num(t *testing.T, v types.AttributeValue) int64 {
	t.Helper()
	n, err := strconv.ParseInt(v.(*types.AttributeValueMemberN).Value, 10, 64)
	if err != nil {
		t.Fatal(err)
	}
	return n
}

func (f *fakeDynamo) GetItem(_ context.Context, in *dynamodb.GetItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.GetItemOutput, error) {
	f.calls = append(f.calls, "GetItem")
	rec, ok := f.items[subOf(in.Key)]
	if !ok {
		return &dynamodb.GetItemOutput{}, nil
	}
	item, err := attributevalue.MarshalMap(rec)
	return &dynamodb.GetItemOutput{Item: item}, err
}

func (f *fakeDynamo) UpdateItem(_ context.Context, in *dynamodb.UpdateItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.UpdateItemOutput, error) {
	f.calls = append(f.calls, "UpdateItem")
	if aws.ToString(in.ConditionExpression) != "attribute_exists(#items) AND #ttl >= :epoch" {
		f.t.Fatalf("unexpected update condition %q", aws.ToString(in.ConditionExpression))
	}
	sub, v := subOf(in.Key), in.ExpressionAttributeValues
	rec, ok := f.items[sub]
	if !ok || rec.Items == nil || rec.TTL < num(f.t, v[":epoch"]) {
		return nil, ccf()
	}
	pid := in.ExpressionAttributeNames["#pid"]
	if q, ok := v[":qty"]; ok {
		rec.Items[pid] = int(num(f.t, q))
	} else {
		delete(rec.Items, pid)
	}
	rec.UpdatedAt = v[":now"].(*types.AttributeValueMemberS).Value
	rec.TTL = num(f.t, v[":ttl"])
	f.items[sub] = rec
	item, err := attributevalue.MarshalMap(rec)
	return &dynamodb.UpdateItemOutput{Attributes: item}, err
}

func (f *fakeDynamo) PutItem(_ context.Context, in *dynamodb.PutItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.PutItemOutput, error) {
	f.calls = append(f.calls, "PutItem")
	if aws.ToString(in.ConditionExpression) != "attribute_not_exists(customer_sub) OR #ttl < :epoch" {
		f.t.Fatalf("unexpected put condition %q", aws.ToString(in.ConditionExpression))
	}
	var rec record
	if err := attributevalue.UnmarshalMap(in.Item, &rec); err != nil {
		return nil, err
	}
	if old, ok := f.items[rec.CustomerSub]; ok && old.TTL >= num(f.t, in.ExpressionAttributeValues[":epoch"]) {
		return nil, ccf()
	}
	f.items[rec.CustomerSub] = rec
	return &dynamodb.PutItemOutput{}, nil
}

func (f *fakeDynamo) DeleteItem(_ context.Context, in *dynamodb.DeleteItemInput, _ ...func(*dynamodb.Options)) (*dynamodb.DeleteItemOutput, error) {
	f.calls = append(f.calls, "DeleteItem")
	delete(f.items, subOf(in.Key))
	return &dynamodb.DeleteItemOutput{}, nil
}

var fixedNow = time.Date(2026, 11, 5, 10, 0, 0, 0, time.UTC)

func newDynamoTestStore(t *testing.T) (*dynamoStore, *fakeDynamo) {
	f := newFakeDynamo(t)
	return &dynamoStore{api: f, table: "lesson14-dev-cart", ttlDays: 7, now: func() time.Time { return fixedNow }}, f
}

func TestDynamoStore_PutCreatesItemWithTTL(t *testing.T) {
	s, f := newDynamoTestStore(t)
	c, err := s.PutItem(context.Background(), "sub-1", "p-0001", 2)
	if err != nil {
		t.Fatalf("PutItem: %v", err)
	}
	// No cart yet: the conditional update fails and is retried as a create.
	if got := strings.Join(f.calls, ","); got != "UpdateItem,PutItem" {
		t.Errorf("calls = %s, want UpdateItem,PutItem", got)
	}
	rec := f.items["sub-1"]
	if want := fixedNow.Add(7 * 24 * time.Hour).Unix(); rec.TTL != want {
		t.Errorf("ttl = %d, want now+7d = %d", rec.TTL, want)
	}
	if rec.UpdatedAt != "2026-11-05T10:00:00Z" || rec.Items["p-0001"] != 2 {
		t.Errorf("record = %+v", rec)
	}
	if len(c.Items) != 1 || c.Items[0] != (Item{ProductID: "p-0001", Quantity: 2}) || !c.UpdatedAt.Equal(fixedNow) {
		t.Errorf("cart = %+v", c)
	}

	// A second line updates the live item in place and pushes the TTL out from the new now.
	s.now = func() time.Time { return fixedNow.Add(time.Hour) }
	f.calls = nil
	c, err = s.PutItem(context.Background(), "sub-1", "p-0002", 1)
	if err != nil {
		t.Fatalf("second PutItem: %v", err)
	}
	if got := strings.Join(f.calls, ","); got != "UpdateItem" {
		t.Errorf("calls = %s, want UpdateItem", got)
	}
	if want := fixedNow.Add(time.Hour + 7*24*time.Hour).Unix(); f.items["sub-1"].TTL != want {
		t.Errorf("ttl = %d, want %d", f.items["sub-1"].TTL, want)
	}
	if len(c.Items) != 2 {
		t.Errorf("cart = %+v, want two lines", c)
	}
}

func TestDynamoStore_QuantityZeroRemovesLine(t *testing.T) {
	s, f := newDynamoTestStore(t)
	ctx := context.Background()
	for _, pid := range []string{"p-0001", "p-0002"} {
		if _, err := s.PutItem(ctx, "sub-1", pid, 3); err != nil {
			t.Fatalf("PutItem %s: %v", pid, err)
		}
	}
	c, err := s.PutItem(ctx, "sub-1", "p-0001", 0)
	if err != nil {
		t.Fatalf("PutItem qty 0: %v", err)
	}
	if len(c.Items) != 1 || c.Items[0].ProductID != "p-0002" {
		t.Errorf("cart = %+v, want only p-0002", c)
	}
	if _, ok := f.items["sub-1"].Items["p-0001"]; ok {
		t.Errorf("stored items = %v, p-0001 still present", f.items["sub-1"].Items)
	}

	// Removing from a cart that does not exist creates nothing.
	f.calls = nil
	c, err = s.PutItem(ctx, "sub-2", "p-0001", 0)
	if err != nil || len(c.Items) != 0 {
		t.Errorf("qty 0 on no cart = %+v, %v", c, err)
	}
	if got := strings.Join(f.calls, ","); got != "UpdateItem" {
		t.Errorf("calls = %s, want UpdateItem only", got)
	}
	if _, ok := f.items["sub-2"]; ok {
		t.Error("qty 0 created a cart")
	}
}

func TestDynamoStore_ExpiredItemReadsEmptyAndIsReplaced(t *testing.T) {
	s, f := newDynamoTestStore(t)
	ctx := context.Background()
	f.items["sub-1"] = record{
		CustomerSub: "sub-1",
		Items:       map[string]int{"p-old": 5},
		UpdatedAt:   "2026-10-01T00:00:00Z",
		TTL:         fixedNow.Add(-time.Minute).Unix(), // expired, not yet deleted by DynamoDB
	}
	c, err := s.Get(ctx, "sub-1")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if len(c.Items) != 0 || !c.UpdatedAt.IsZero() || c.CustomerSub != "sub-1" {
		t.Errorf("expired cart = %+v, want empty", c)
	}

	// The first write after expiry starts a fresh cart instead of reviving the old lines.
	f.calls = nil
	c, err = s.PutItem(ctx, "sub-1", "p-new", 1)
	if err != nil {
		t.Fatalf("PutItem: %v", err)
	}
	if got := strings.Join(f.calls, ","); got != "UpdateItem,PutItem" {
		t.Errorf("calls = %s, want UpdateItem,PutItem", got)
	}
	if len(c.Items) != 1 || c.Items[0].ProductID != "p-new" {
		t.Errorf("cart = %+v, want only p-new", c)
	}
}

func TestDynamoStore_ClearDeletes(t *testing.T) {
	s, _ := newDynamoTestStore(t)
	ctx := context.Background()
	if _, err := s.PutItem(ctx, "sub-1", "p-0001", 1); err != nil {
		t.Fatal(err)
	}
	if err := s.Clear(ctx, "sub-1"); err != nil {
		t.Fatalf("Clear: %v", err)
	}
	if c, _ := s.Get(ctx, "sub-1"); len(c.Items) != 0 {
		t.Errorf("cart after Clear = %+v", c)
	}
	if err := s.Clear(ctx, "sub-none"); err != nil {
		t.Errorf("Clear on no cart: %v", err)
	}
}
