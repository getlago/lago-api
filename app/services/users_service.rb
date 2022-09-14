# frozen_string_literal: true

class UsersService < BaseService
  def login(email, password)
    result.user = User.find_by(email: email)&.authenticate(password)
    result.token = generate_token if result.user

    return result.fail!(code: 'incorrect_login_or_password') unless result.user

    # Note: We're tracking the first membership linked to the user.
    SegmentIdentifyJob.perform_later(membership_id: "membership/#{result.user.memberships.first.id}")

    result
  end

  def register(email, password, organization_name)
    result.user = User.find_or_initialize_by(email: email)

    if result.user.id
      result.fail!(code: 'user_already_exists')

      return result
    end

    result.organization = Organization.create!(name: organization_name)
    result.token = generate_token

    create_user_and_membership(result, password)

    SegmentIdentifyJob.perform_later(membership_id: "membership/#{result.membership.id}")
    track_organization_registered(result.organization, result.membership)

    result
  end

  def register_from_invite(email, password, organization_id)
    result.user = User.find_or_initialize_by(email: email)

    return result.fail!(code: 'user_already_exists') if result.user.id

    result.organization = Organization.find(organization_id)
    result.token = generate_token

    create_user_and_membership(result, password)

    result
  end

  def new_token(user)
    result.user = user
    result.token = generate_token
    result
  end

  private

  def create_user_and_membership(result, password)
    ActiveRecord::Base.transaction do
      result.user.password = password
      result.user.save!

      result.membership = Membership.create!(
        user: result.user,
        organization: result.organization,
      )

      result
    end
  rescue ActiveRecord::RecordInvalid => e
    result.record_validation_failure!(record: e.record)
  end

  def generate_token
    JWT.encode(payload, ENV['SECRET_KEY_BASE'], 'HS256')
  rescue StandardError => e
    result.fail!(code: 'token_encoding_error', message: e.message)
  end

  def payload
    {
      sub: result.user.id,
      exp: Time.now.to_i + 8640 # 6 hours expiration
    }
  end

  def track_organization_registered(organization, membership)
    SegmentTrackJob.perform_later(
      membership_id: "membership/#{membership.id}",
      event: 'organization_registered',
      properties: {
        organization_name: organization.name,
        organization_id: organization.id,
      }
    )
  end
end
