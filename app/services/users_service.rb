# frozen_string_literal: true

class UsersService < BaseService
  include TypedResults

  RESULTS = {
    login: BaseResult[:user, :token, :needs_organization],
    register: BaseResult[:user, :organization, :membership, :token],
    register_from_invite: BaseResult[:user, :organization, :membership, :token]
  }.freeze

  # Compared when no user matches and self-serve is on, so an unknown email costs one bcrypt like a known one.
  DUMMY_PASSWORD = Concurrent::Delay.new do
    BCrypt::Password.create(SecureRandom.hex(32), cost: ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost)
  end

  private

  def login(email, password)
    # NOTE: Null byte injection. Prevent 500 errors.
    if email.include?("\u0000") || password.include?("\u0000")
      return result.single_validation_failure!(error_code: "incorrect_login_or_password")
    end

    user = find_user_by_email(email)
    DUMMY_PASSWORD.value.is_password?(password) if user.nil? && Lago::SelfServe.enabled?
    result.user = user&.authenticate(password)

    # The account state is read only after a correct password, and every refusal gives the same answer.
    needs_organization = result.user.present? && result.user.needs_organization?
    can_log_in = result.user.present? && (needs_organization || result.user.memberships.active.any?)
    return result.single_validation_failure!(error_code: "incorrect_login_or_password") unless can_log_in

    # A user without an organization has no organization login policy yet.
    unless needs_organization || result.user.login_method_allowed?(Organizations::AuthenticationMethods::EMAIL_PASSWORD)
      return result.single_validation_failure!(
        error_code: "login_method_not_authorized",
        field: Organizations::AuthenticationMethods::EMAIL_PASSWORD
      )
    end

    result.token = generate_token
    result.needs_organization = needs_organization

    # NOTE: We're tracking the oldest membership linked to the user. A user without one has no Segment identity yet.
    membership = result.user.memberships.active.order(:created_at).first
    SegmentIdentifyJob.perform_later(membership_id: "membership/#{membership.id}") if membership

    UserDevices::RegisterService.call!(user: result.user)

    result
  end

  def register(email, password, organization_name)
    if Lago::SelfServe.signup_disabled?
      return result.forbidden_failure!(code: "signup_disabled")
    end

    if find_user_by_email(email)
      result.single_validation_failure!(field: :email, error_code: "user_already_exists")

      return result
    end

    ActiveRecord::Base.transaction do
      result.user = User.create!(email:, password:)

      result.organization = Organizations::CreateService
        .call!(name: organization_name, document_numbering: "per_organization")
        .organization

      result.membership = Membership.create!(
        user: result.user,
        organization: result.organization
      )

      MembershipRole.create!(
        organization: result.organization,
        membership: result.membership,
        role: Role.admins.first!
      )

      result.token = generate_token
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    SegmentIdentifyJob.perform_later(membership_id: "membership/#{result.membership.id}")
    track_organization_registered(result.organization, result.membership)

    register_security_log(result)

    # Skip log: user.signed_up already covers signup
    UserDevices::RegisterService.call!(user: result.user, skip_log: true)

    result
  end

  def register_from_invite(invite, password, login_method:)
    ActiveRecord::Base.transaction do
      # Held until this transaction ends: serializes with a self-serve signup confirming the same address, since
      # users.email has no unique index.
      Users::EmailLockService.call(email: invite.email) { nil }

      # NOTE: Same case insensitive lookup as Invite#existing_user, so an invitation never creates
      #       a second user for an email that only differs by case.
      user = invite.existing_user || User.new(email: invite.email)

      # The caller's earlier lookup can become stale, so authenticate the account found here.
      if user.persisted? && login_method == Organizations::AuthenticationMethods::EMAIL_PASSWORD
        authentication_result = Invites::AuthenticateUserService.call(user:, password:)
        return result.fail_with_error!(authentication_result.error) unless authentication_result.success?
      end

      # NOTE: The password is only set when the user is created. The password of an existing user
      #       is never reset by an invitation.
      if user.new_record?
        user.password = password
        user.save!
        # The address now has a user: its open self-serve signup attempts stop and drop their password digests.
        Signups::CloseAttemptsService.call!(normalized_email: PendingSignup.normalize_email(invite.email))
      end

      result.user = user
      result.organization = invite.organization

      result.membership = Memberships::CreateFromInviteService.call!(invite:, user:).membership

      result.token = generate_token
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    result
  rescue BaseLockService::FailedToAcquireLock
    result.lock_acquisition_failure!(message: "email lock not acquired")
  end

  def generate_token
    Utils::AuthToken.encode(user: result.user, login_method: Organizations::AuthenticationMethods::EMAIL_PASSWORD)
  rescue => e
    result.service_failure!(code: "token_encoding_error", message: e.message)
  end

  def find_user_by_email(email)
    User.lookup_by_email(email)
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

  def register_security_log(result)
    Utils::SecurityLog.produce(
      organization: result.organization,
      log_type: "user",
      log_event: "user.signed_up",
      user: result.user,
      resources: {
        email: result.user.email,
        roles: result.membership.roles.map(&:code)
      },
      skip_organization_check: true
    )
  end
end
