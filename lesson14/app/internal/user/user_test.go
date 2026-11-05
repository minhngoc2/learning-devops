package user

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	cip "github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
)

// fakeAuth registers emails in a map; Login succeeds only with the registered password.
type fakeAuth struct {
	users  map[string]string // email → password
	subs   map[string]string // email → sub
	logins int
	n      int
}

// Like Cognito after the retry fix, registering a known email returns its existing sub.
func (f *fakeAuth) Register(_ context.Context, email, password, _ string) (string, error) {
	if sub, ok := f.subs[email]; ok {
		return sub, nil
	}
	f.users[email] = password
	f.n++
	f.subs[email] = "sub-" + string(rune('0'+f.n))
	return f.subs[email], nil
}

func (f *fakeAuth) Login(_ context.Context, email, password string) (Tokens, error) {
	f.logins++
	if pw, ok := f.users[email]; !ok || pw != password {
		return Tokens{}, ErrInvalidCredentials
	}
	return Tokens{IDToken: "id", AccessToken: "access", RefreshToken: "refresh", ExpiresIn: 3600}, nil
}

func newRoutes() (http.Handler, Store) {
	s := NewMemoryStore()
	return Routes(&fakeAuth{users: map[string]string{}, subs: map[string]string{}}, s, slog.New(slog.NewJSONHandler(io.Discard, nil))), s
}

func do(h http.Handler, method, path, sub, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	if sub != "" {
		r.Header.Set("X-Customer-Sub", sub)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}

const aliceBody = `{"email":"Alice@Example.com","password":"Passw0rd!","display_name":"Alice"}`

func TestRegister_StoresCustomerAndReturns201(t *testing.T) {
	h, s := newRoutes()
	rec := do(h, "POST", "/api/users/register", "", aliceBody)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d (%s)", rec.Code, rec.Body)
	}
	var got map[string]any
	_ = json.NewDecoder(rec.Body).Decode(&got)
	if got["sub"] != "sub-1" || got["email"] != "alice@example.com" || got["display_name"] != "Alice" || got["created_at"] == nil {
		t.Errorf("body = %v", got)
	}
	c, err := s.Get(context.Background(), "sub-1")
	if err != nil || c.Email != "alice@example.com" || c.DisplayName != "Alice" {
		t.Errorf("stored = %+v, %v", c, err)
	}

	for _, body := range []string{
		`{"email":"","password":"x","display_name":"A"}`,
		`{"email":"no-at-sign","password":"x","display_name":"A"}`,
		`{"email":"b@example.com","password":"","display_name":"A"}`,
		`{"email":"b@example.com","password":"x","display_name":" "}`,
		`nope`,
	} {
		if rec := do(h, "POST", "/api/users/register", "", body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s → %d, want 400", body, rec.Code)
		}
	}
}

func TestRegister_DuplicateEmail409(t *testing.T) {
	h, _ := newRoutes()
	do(h, "POST", "/api/users/register", "", aliceBody)
	rec := do(h, "POST", "/api/users/register", "", `{"email":"alice@example.com","password":"other","display_name":"A2"}`)
	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"email already registered"}` {
		t.Errorf("body = %s", got)
	}
}

func TestLogin_BadPassword401(t *testing.T) {
	h, _ := newRoutes()
	do(h, "POST", "/api/users/register", "", aliceBody)

	for _, body := range []string{
		`{"email":"alice@example.com","password":"wrong"}`,
		`{"email":"nobody@example.com","password":"Passw0rd!"}`,
	} {
		rec := do(h, "POST", "/api/users/login", "", body)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s → %d, want 401", body, rec.Code)
		}
		if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"invalid credentials"}` {
			t.Errorf("body = %s", got)
		}
	}

	rec := do(h, "POST", "/api/users/login", "", `{"email":" ALICE@example.com","password":"Passw0rd!"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("good login = %d (%s)", rec.Code, rec.Body)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"id_token":"id","access_token":"access","refresh_token":"refresh","expires_in":3600}` {
		t.Errorf("tokens = %s", got)
	}
}

func TestMe_ReturnsStoredCustomer(t *testing.T) {
	h, _ := newRoutes()
	do(h, "POST", "/api/users/register", "", aliceBody)

	if rec := do(h, "GET", "/api/users/me", "", ""); rec.Code != http.StatusUnauthorized {
		t.Errorf("no identity → %d, want 401", rec.Code)
	}
	if rec := do(h, "GET", "/api/users/me", "sub-unknown", ""); rec.Code != http.StatusNotFound {
		t.Errorf("unknown sub → %d, want 404", rec.Code)
	}
	rec := do(h, "GET", "/api/users/me", "sub-1", "")
	var got map[string]any
	_ = json.NewDecoder(rec.Body).Decode(&got)
	if rec.Code != http.StatusOK || got["sub"] != "sub-1" || got["email"] != "alice@example.com" {
		t.Errorf("me = %d %v", rec.Code, got)
	}
}

func TestLocalAuth_RoundTrip(t *testing.T) {
	ctx := context.Background()
	a := NewLocalAuth()
	sub, err := a.Register(ctx, "a@example.com", "pw", "A")
	if err != nil || sub == "" {
		t.Fatalf("Register = %q, %v", sub, err)
	}
	if again, err := a.Register(ctx, "a@example.com", "pw2", "A"); err != nil || again != sub {
		t.Errorf("duplicate = %q, %v; want the existing sub %q", again, err, sub)
	}
	if _, err := a.Login(ctx, "a@example.com", "pw2"); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("duplicate register changed the password: %v", err)
	}
	tok, err := a.Login(ctx, "a@example.com", "pw")
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	want := Tokens{IDToken: "local:" + sub + ":a@example.com", AccessToken: "local:" + sub + ":a@example.com", ExpiresIn: 3600}
	if tok != want {
		t.Errorf("tokens = %+v, want %+v", tok, want)
	}
	if _, err := a.Login(ctx, "a@example.com", "bad"); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("bad password err = %v", err)
	}
	if _, err := a.Login(ctx, "x@example.com", "pw"); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("unknown email err = %v", err)
	}
}

// fakeCognito is a tiny user pool: SignUp adds an UNCONFIRMED user, the admin calls confirm and verify it.
// It records every call; signUpErr, confirmErr and authErr override the outcome of their call.
type fakeCognito struct {
	calls                          []string
	signUpErr, confirmErr, authErr error
	users                          map[string]*fakePoolUser // username (email) → user
}

type fakePoolUser struct {
	sub, status string
	verified    bool
}

func (f *fakeCognito) SignUp(_ context.Context, in *cip.SignUpInput, _ ...func(*cip.Options)) (*cip.SignUpOutput, error) {
	f.calls = append(f.calls, "SignUp:"+aws.ToString(in.ClientId)+":"+aws.ToString(in.Username)+":"+attrs(in.UserAttributes))
	if f.signUpErr != nil {
		return nil, f.signUpErr
	}
	if f.users == nil {
		f.users = map[string]*fakePoolUser{}
	}
	if _, ok := f.users[aws.ToString(in.Username)]; ok {
		return nil, &types.UsernameExistsException{Message: aws.String("User already exists")}
	}
	f.users[aws.ToString(in.Username)] = &fakePoolUser{sub: "cognito-sub", status: string(types.UserStatusTypeUnconfirmed)}
	return &cip.SignUpOutput{UserSub: aws.String("cognito-sub")}, nil
}

func (f *fakeCognito) AdminConfirmSignUp(_ context.Context, in *cip.AdminConfirmSignUpInput, _ ...func(*cip.Options)) (*cip.AdminConfirmSignUpOutput, error) {
	f.calls = append(f.calls, "AdminConfirmSignUp:"+aws.ToString(in.UserPoolId)+":"+aws.ToString(in.Username))
	if f.confirmErr != nil {
		return nil, f.confirmErr
	}
	if u, ok := f.users[aws.ToString(in.Username)]; ok {
		u.status = string(types.UserStatusTypeConfirmed)
	}
	return &cip.AdminConfirmSignUpOutput{}, nil
}

func (f *fakeCognito) AdminUpdateUserAttributes(_ context.Context, in *cip.AdminUpdateUserAttributesInput, _ ...func(*cip.Options)) (*cip.AdminUpdateUserAttributesOutput, error) {
	f.calls = append(f.calls, "AdminUpdateUserAttributes:"+aws.ToString(in.UserPoolId)+":"+attrs(in.UserAttributes))
	if u, ok := f.users[aws.ToString(in.Username)]; ok {
		u.verified = true
	}
	return &cip.AdminUpdateUserAttributesOutput{}, nil
}

func (f *fakeCognito) AdminGetUser(_ context.Context, in *cip.AdminGetUserInput, _ ...func(*cip.Options)) (*cip.AdminGetUserOutput, error) {
	f.calls = append(f.calls, "AdminGetUser:"+aws.ToString(in.UserPoolId)+":"+aws.ToString(in.Username))
	u, ok := f.users[aws.ToString(in.Username)]
	if !ok {
		return nil, &types.UserNotFoundException{}
	}
	return &cip.AdminGetUserOutput{
		Username:   aws.String(u.sub),
		UserStatus: types.UserStatusType(u.status),
		UserAttributes: []types.AttributeType{
			{Name: aws.String("sub"), Value: aws.String(u.sub)},
			{Name: aws.String("email_verified"), Value: aws.String(map[bool]string{true: "true", false: "false"}[u.verified])},
		},
	}, nil
}

func (f *fakeCognito) InitiateAuth(_ context.Context, in *cip.InitiateAuthInput, _ ...func(*cip.Options)) (*cip.InitiateAuthOutput, error) {
	f.calls = append(f.calls, "InitiateAuth:"+string(in.AuthFlow)+":"+in.AuthParameters["USERNAME"])
	if f.authErr != nil {
		return nil, f.authErr
	}
	return &cip.InitiateAuthOutput{AuthenticationResult: &types.AuthenticationResultType{
		IdToken: aws.String("id"), AccessToken: aws.String("access"), RefreshToken: aws.String("refresh"), ExpiresIn: 3600,
	}}, nil
}

func attrs(as []types.AttributeType) string {
	parts := []string{}
	for _, a := range as {
		parts = append(parts, aws.ToString(a.Name)+"="+aws.ToString(a.Value))
	}
	return strings.Join(parts, ",")
}

func TestCognitoAuth_CallSequenceAndErrors(t *testing.T) {
	ctx := context.Background()
	f := &fakeCognito{}
	a := cognitoAuth{api: f, poolID: "pool", clientID: "client"}

	sub, err := a.Register(ctx, "a@example.com", "pw", "Alice")
	if err != nil || sub != "cognito-sub" {
		t.Fatalf("Register = %q, %v", sub, err)
	}
	tok, err := a.Login(ctx, "a@example.com", "pw")
	if err != nil || tok != (Tokens{IDToken: "id", AccessToken: "access", RefreshToken: "refresh", ExpiresIn: 3600}) {
		t.Fatalf("Login = %+v, %v", tok, err)
	}
	want := []string{
		"SignUp:client:a@example.com:email=a@example.com,name=Alice",
		"AdminConfirmSignUp:pool:a@example.com",
		"AdminUpdateUserAttributes:pool:email_verified=true",
		"InitiateAuth:USER_PASSWORD_AUTH:a@example.com",
	}
	if strings.Join(f.calls, "\n") != strings.Join(want, "\n") {
		t.Errorf("calls =\n%s\nwant\n%s", strings.Join(f.calls, "\n"), strings.Join(want, "\n"))
	}

	// A second sign-up of a complete account returns the existing sub; the handler answers 409 because
	// the profile row exists. Nothing is confirmed or verified again.
	f.calls = nil
	if sub, err := a.Register(ctx, "a@example.com", "other", "A"); err != nil || sub != "cognito-sub" {
		t.Errorf("existing user → %q, %v; want cognito-sub, nil", sub, err)
	}
	if want := "SignUp:client:a@example.com:email=a@example.com,name=A\nAdminGetUser:pool:a@example.com"; strings.Join(f.calls, "\n") != want {
		t.Errorf("calls for an existing user =\n%s\nwant\n%s", strings.Join(f.calls, "\n"), want)
	}
	f.signUpErr = &types.InvalidPasswordException{Message: aws.String("too short")}
	if _, err := a.Register(ctx, "a@example.com", "pw", "A"); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("InvalidPassword → %v", err)
	}
	for _, e := range []error{&types.NotAuthorizedException{}, &types.UserNotFoundException{}} {
		f.authErr = e
		if _, err := a.Login(ctx, "a@example.com", "pw"); !errors.Is(err, ErrInvalidCredentials) {
			t.Errorf("%T → %v", e, err)
		}
	}
}

func TestRegister_RetryAfterPartialFailureCompletes(t *testing.T) {
	f := &fakeCognito{confirmErr: errors.New("throttled")}
	s := NewMemoryStore()
	h := Routes(cognitoAuth{api: f, poolID: "pool", clientID: "client"}, s, slog.New(slog.NewJSONHandler(io.Discard, nil)))

	// First attempt: the pool user is created, then confirming fails, so no profile row is written.
	if rec := do(h, "POST", "/api/users/register", "", aliceBody); rec.Code != http.StatusInternalServerError {
		t.Fatalf("first attempt = %d (%s), want 500", rec.Code, rec.Body)
	}
	if _, err := s.Get(context.Background(), "cognito-sub"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("profile after failed attempt: %v, want ErrNotFound", err)
	}

	// Retry: SignUp says the user exists; the adapter finishes confirm + verify and the profile is created.
	f.confirmErr, f.calls = nil, nil
	rec := do(h, "POST", "/api/users/register", "", aliceBody)
	if rec.Code != http.StatusCreated {
		t.Fatalf("retry = %d (%s), want 201", rec.Code, rec.Body)
	}
	want := []string{
		"SignUp:client:alice@example.com:email=alice@example.com,name=Alice",
		"AdminGetUser:pool:alice@example.com",
		"AdminConfirmSignUp:pool:alice@example.com",
		"AdminUpdateUserAttributes:pool:email_verified=true",
	}
	if strings.Join(f.calls, "\n") != strings.Join(want, "\n") {
		t.Errorf("retry calls =\n%s\nwant\n%s", strings.Join(f.calls, "\n"), strings.Join(want, "\n"))
	}
	if u := f.users["alice@example.com"]; u.status != string(types.UserStatusTypeConfirmed) || !u.verified {
		t.Errorf("pool user = %+v, want CONFIRMED and verified", *u)
	}
	if c, err := s.Get(context.Background(), "cognito-sub"); err != nil || c.Email != "alice@example.com" || c.DisplayName != "Alice" {
		t.Errorf("profile = %+v, %v", c, err)
	}

	// Once complete, registering again is a conflict and leaves the profile alone.
	rec = do(h, "POST", "/api/users/register", "", `{"email":"alice@example.com","password":"x","display_name":"Mallory"}`)
	if rec.Code != http.StatusConflict {
		t.Fatalf("third attempt = %d, want 409", rec.Code)
	}
	if c, _ := s.Get(context.Background(), "cognito-sub"); c.DisplayName != "Alice" {
		t.Errorf("display_name = %q after a conflicting register, want Alice", c.DisplayName)
	}
}

func TestLogin_EmptyCredentials401WithoutCallingAuth(t *testing.T) {
	a := &fakeAuth{users: map[string]string{"alice@example.com": ""}, subs: map[string]string{}}
	h := Routes(a, NewMemoryStore(), slog.New(slog.NewJSONHandler(io.Discard, nil)))
	for _, body := range []string{
		`{"email":"","password":"Passw0rd!"}`,
		`{"email":"  ","password":"Passw0rd!"}`,
		`{"email":"alice@example.com","password":""}`,
		`{}`,
	} {
		rec := do(h, "POST", "/api/users/login", "", body)
		if rec.Code != http.StatusUnauthorized || strings.TrimSpace(rec.Body.String()) != `{"error":"invalid credentials"}` {
			t.Errorf("%s → %d %s, want 401 invalid credentials", body, rec.Code, rec.Body)
		}
	}
	if a.logins != 0 {
		t.Errorf("Auth.Login called %d times, want 0", a.logins)
	}
}
