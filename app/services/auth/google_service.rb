# frozen_string_literal: true

module Auth
  class GoogleService < BaseService
    include TypedResults

    BASE_SCOPE = %w[profile email openid].freeze

    RESULTS = {
      authorize_url: BaseResult[:url, :state_secret],
      claims: BaseResult[:claims],
      login: BaseResult[:user, :token],
      register_user: BaseResult[:user, :organization, :membership, :token],
      accept_invite: Invites::AcceptService::Result
    }.freeze

    private

    def authorize_url(request)
      ensure_google_auth_setup
      return result unless result.success?

      if Lago::SelfServe.enabled?
        # Bound to the tab that keeps state_secret, and to the code through PKCE.
        issued = GoogleOauthState.issue
        authorizer = Google::Auth::UserAuthorizer.new(client_id, BASE_SCOPE, nil, callback_url, code_verifier: issued.code_verifier)
        result.url = authorizer.get_authorization_url(state: issued.state)
        result.state_secret = issued.secret
      else
        authorizer = Google::Auth::WebUserAuthorizer.new(
          client_id,
          BASE_SCOPE,
          nil, # token_store is nil because we don't need to store the token
          callback_url
        )
        result.url = authorizer.get_authorization_url(request:)
      end

      result
    end

    def login(code, state: nil, state_secret: nil)
      ensure_google_auth_setup
      return result unless result.success?

      code_verifier = verified_code_verifier(state, state_secret) if Lago::SelfServe.enabled?
      return result unless result.success?

      google_oidc = oidc_verifier(code:, code_verifier:)
      user = find_user_by_email(google_oidc["email"])
      refusal = GoogleLoginRules.refusal(user, google_oidc)
      return result.single_validation_failure!(**refusal) if refusal

      result.user = user
      UserDevices::RegisterService.call!(user:)
      generate_token
    rescue Google::Auth::IDTokens::VerificationError
      result.single_validation_failure!(error_code: "invalid_google_token")
    rescue Signet::AuthorizationError
      result.single_validation_failure!(error_code: "invalid_google_code")
    end

    def register_user(code, organization_name)
      ensure_google_auth_setup
      return result unless result.success?

      google_oidc = oidc_verifier(code:)

      register(google_oidc["email"], organization_name)
    rescue Google::Auth::IDTokens::VerificationError
      result.single_validation_failure!(error_code: "invalid_google_token")
    rescue Signet::AuthorizationError
      result.single_validation_failure!(error_code: "invalid_google_code")
    end

    # With self-serve on, googleAuthUrl always sends a PKCE challenge, so the code can only be redeemed with the
    # verifier of its flow.
    def accept_invite(code, invite_token, state: nil, state_secret: nil)
      ensure_google_auth_setup
      return result unless result.success?

      code_verifier = verified_code_verifier(state, state_secret) if Lago::SelfServe.enabled?
      return result unless result.success?

      google_oidc = oidc_verifier(code:, code_verifier:)
      invite = Invite.find_by(token: invite_token, status: :pending)

      return result.not_found_failure!(resource: "invite") unless invite

      unless google_oidc["email"] == invite.email
        return result.single_validation_failure!(error_code: "invite_email_mistmatch")
      end

      Invites::AcceptService.new.call(
        invite:,
        email: google_oidc["email"],
        token: invite_token,
        password: SecureRandom.hex,
        login_method: Organizations::AuthenticationMethods::GOOGLE_OAUTH
      )
    rescue Google::Auth::IDTokens::VerificationError
      result.single_validation_failure!(error_code: "invalid_google_token")
    rescue Signet::AuthorizationError
      result.single_validation_failure!(error_code: "invalid_google_code")
    end

    # The verified ID token claims of a self-serve signup. The state is always required.
    def claims(code, state:, state_secret:)
      ensure_google_auth_setup
      return result unless result.success?

      code_verifier = verified_code_verifier(state, state_secret)
      return result unless result.success?

      result.claims = oidc_verifier(code:, code_verifier:)
      result
    rescue Google::Auth::IDTokens::VerificationError
      result.single_validation_failure!(error_code: "invalid_google_token")
    rescue Signet::AuthorizationError
      result.single_validation_failure!(error_code: "invalid_google_code")
    end

    def verified_code_verifier(state, state_secret)
      code_verifier = GoogleOauthState.verify(state:, secret: state_secret)
      result.single_validation_failure!(error_code: "invalid_google_state") unless code_verifier
      code_verifier
    end

    def callback_url
      "#{Rails.application.config.lago_front_url}/auth/google/callback"
    end

    def generate_token
      result.token = Utils::AuthToken.encode(user: result.user, login_method: Organizations::AuthenticationMethods::GOOGLE_OAUTH)
      result
    rescue => e
      result.service_failure!(code: "token_encoding_error", message: e.message)
    end

    def register(email, organization_name)
      if Lago::SelfServe.signup_disabled?
        return result.forbidden_failure!(code: "signup_disabled")
      end

      if find_user_by_email(email)
        result.single_validation_failure!(field: :email, error_code: "user_already_exists")

        return result
      end

      ActiveRecord::Base.transaction do
        result.user = User.create!(email:, password: SecureRandom.hex)

        result.organization = Organizations::CreateService
          .call!(name: organization_name, document_numbering: "per_organization")
          .organization

        result.membership = Membership.create!(
          user: result.user,
          organization: result.organization
        )

        role = Role.find_by!(admin: true)
        MembershipRole.create!(membership: result.membership, organization: result.organization, role:)

        generate_token
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      SegmentIdentifyJob.perform_later(membership_id: "membership/#{result.membership.id}")
      track_organization_registered(result.organization, result.membership)

      # Skip log: user.signed_up already covers signup
      UserDevices::RegisterService.call!(user: result.user, skip_log: true)

      result
    end

    def track_organization_registered(organization, membership)
      SegmentTrackJob.perform_later(
        membership_id: "membership/#{membership.id}",
        event: "organization_registered",
        properties: {
          organization_name: organization.name,
          organization_id: organization.id,
          email: membership.user.email
        }
      )
    end

    def find_user_by_email(email)
      User.lookup_by_email(email)
    end

    def client_id
      @client_id ||= Google::Auth::ClientId.new(ENV["GOOGLE_AUTH_CLIENT_ID"], ENV["GOOGLE_AUTH_CLIENT_SECRET"])
    end

    def ensure_google_auth_setup
      return if ENV["GOOGLE_AUTH_CLIENT_ID"].present? && ENV["GOOGLE_AUTH_CLIENT_SECRET"].present?

      result.service_failure!(code: "google_auth_missing_setup", message: "Google auth is not set up")
    end

    def oidc_verifier(code:, code_verifier: nil)
      authorizer = Google::Auth::UserAuthorizer.new(
        client_id,
        BASE_SCOPE,
        nil, # token_store is nil because we don't need to store the token
        callback_url,
        code_verifier:
      )

      credentials = authorizer.get_credentials_from_code(code:)
      Google::Auth::IDTokens.verify_oidc(credentials.id_token, aud: ENV["GOOGLE_AUTH_CLIENT_ID"])
    end
  end
end
