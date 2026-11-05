package user

import (
	"context"
	"errors"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	cip "github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider"
	"github.com/aws/aws-sdk-go-v2/service/cognitoidentityprovider/types"
)

// cognitoAPI is the part of the Cognito client the adapter uses (a seam for tests).
type cognitoAPI interface {
	SignUp(ctx context.Context, in *cip.SignUpInput, opts ...func(*cip.Options)) (*cip.SignUpOutput, error)
	AdminConfirmSignUp(ctx context.Context, in *cip.AdminConfirmSignUpInput, opts ...func(*cip.Options)) (*cip.AdminConfirmSignUpOutput, error)
	AdminUpdateUserAttributes(ctx context.Context, in *cip.AdminUpdateUserAttributesInput, opts ...func(*cip.Options)) (*cip.AdminUpdateUserAttributesOutput, error)
	InitiateAuth(ctx context.Context, in *cip.InitiateAuthInput, opts ...func(*cip.Options)) (*cip.InitiateAuthOutput, error)
}

type cognitoAuth struct {
	api              cognitoAPI
	poolID, clientID string
}

// NewCognitoAuth uses the user pool with email as username and the app client (no secret,
// USER_PASSWORD_AUTH). Email verification is off in the lab, so Register confirms the user and marks the
// email verified with admin calls instead of sending a code.
func NewCognitoAuth(client *cip.Client, poolID, clientID string) Auth {
	return cognitoAuth{api: client, poolID: poolID, clientID: clientID}
}

func (a cognitoAuth) Register(ctx context.Context, email, password, displayName string) (string, error) {
	out, err := a.api.SignUp(ctx, &cip.SignUpInput{
		ClientId: aws.String(a.clientID),
		Username: aws.String(email),
		Password: aws.String(password),
		UserAttributes: []types.AttributeType{
			{Name: aws.String("email"), Value: aws.String(email)},
			{Name: aws.String("name"), Value: aws.String(displayName)},
		},
	})
	var (
		exists     *types.UsernameExistsException
		badPass    *types.InvalidPasswordException
		badParam   *types.InvalidParameterException
		apiMessage string
	)
	switch {
	case errors.As(err, &exists):
		return "", ErrEmailTaken
	case errors.As(err, &badPass):
		apiMessage = badPass.ErrorMessage()
	case errors.As(err, &badParam):
		apiMessage = badParam.ErrorMessage()
	case err != nil:
		return "", fmt.Errorf("cognito sign up: %w", err)
	}
	if apiMessage != "" {
		return "", fmt.Errorf("%w: %s", ErrInvalidInput, apiMessage)
	}

	if _, err := a.api.AdminConfirmSignUp(ctx, &cip.AdminConfirmSignUpInput{
		UserPoolId: aws.String(a.poolID), Username: aws.String(email),
	}); err != nil {
		return "", fmt.Errorf("cognito confirm sign up: %w", err)
	}
	if _, err := a.api.AdminUpdateUserAttributes(ctx, &cip.AdminUpdateUserAttributesInput{
		UserPoolId:     aws.String(a.poolID),
		Username:       aws.String(email),
		UserAttributes: []types.AttributeType{{Name: aws.String("email_verified"), Value: aws.String("true")}},
	}); err != nil {
		return "", fmt.Errorf("cognito verify email: %w", err)
	}
	return aws.ToString(out.UserSub), nil
}

func (a cognitoAuth) Login(ctx context.Context, email, password string) (Tokens, error) {
	out, err := a.api.InitiateAuth(ctx, &cip.InitiateAuthInput{
		ClientId:       aws.String(a.clientID),
		AuthFlow:       types.AuthFlowTypeUserPasswordAuth,
		AuthParameters: map[string]string{"USERNAME": email, "PASSWORD": password},
	})
	var (
		notAuth  *types.NotAuthorizedException
		notFound *types.UserNotFoundException
	)
	if errors.As(err, &notAuth) || errors.As(err, &notFound) {
		return Tokens{}, ErrInvalidCredentials
	}
	if err != nil {
		return Tokens{}, fmt.Errorf("cognito initiate auth: %w", err)
	}
	r := out.AuthenticationResult
	if r == nil { // a challenge (e.g. NEW_PASSWORD_REQUIRED) that the lab never configures
		return Tokens{}, fmt.Errorf("cognito initiate auth: unexpected challenge %q", out.ChallengeName)
	}
	return Tokens{
		IDToken:      aws.ToString(r.IdToken),
		AccessToken:  aws.ToString(r.AccessToken),
		RefreshToken: aws.ToString(r.RefreshToken),
		ExpiresIn:    r.ExpiresIn,
	}, nil
}
