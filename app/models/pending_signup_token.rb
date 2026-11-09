# frozen_string_literal: true

# A verification link of a pending signup. Only the SHA256 digest of the token is stored.
class PendingSignupToken < ApplicationRecord
  STATUSES = {pending: "pending", consumed: "consumed", replaced: "replaced"}.freeze
  TTL = 24.hours
  MAX_PASSWORD_ATTEMPTS = 5
  TOKEN_FORMAT = /\A[A-Za-z0-9_-]{43}\z/

  belongs_to :pending_signup

  enum :status, STATUSES, validate: true

  validates :token_digest, :expires_at, presence: true

  def self.generate
    SecureRandom.urlsafe_base64(32)
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def self.for_token(token)
    find_by(token_digest: digest(token)) if TOKEN_FORMAT.match?(token.to_s)
  end

  # Expiry is derived from the time, never stored as a status.
  def expired?(now = Time.current)
    expires_at <= now
  end

  def locked?
    failed_password_attempts >= MAX_PASSWORD_ATTEMPTS
  end

  # One precedence for the state query and the confirm. Only the holder of the link sees it, so saying that the
  # address has an account reveals nothing to a stranger.
  def verification_status(now = Time.current, by_password: true)
    if consumed? || pending_signup.verified? || pending_signup.email_registered?
      :already_verified
    elsif replaced?
      :replaced
    elsif expired?(now) || pending_signup.closed?
      # A closed attempt with no user ended unconfirmed: its password digest is gone.
      :expired
    elsif by_password && locked?
      # Failed passwords lock only the password path: the attempt's signup secret is a far stronger proof.
      :locked
    else
      :valid
    end
  end
end

# == Schema Information
#
# Table name: pending_signup_tokens
# Database name: primary
#
#  id                       :uuid             not null, primary key
#  consumed_at              :datetime
#  expires_at               :datetime         not null
#  failed_password_attempts :integer          default(0), not null
#  status                   :enum             default("pending"), not null
#  token_digest             :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  pending_signup_id        :uuid             not null
#
# Indexes
#
#  index_pending_signup_tokens_on_expires_at              (expires_at)
#  index_pending_signup_tokens_on_live_pending_signup_id  (pending_signup_id) UNIQUE WHERE (status = 'pending'::pending_signup_token_status)
#  index_pending_signup_tokens_on_pending_signup_id       (pending_signup_id)
#  index_pending_signup_tokens_on_token_digest            (token_digest) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (pending_signup_id => pending_signups.id) ON DELETE => cascade
#
