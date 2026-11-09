# frozen_string_literal: true

# One Step 1 attempt of the self-serve signup. Only Signups::ConfirmService, given this attempt's own proof, writes
# verified_at and user_id, which make its signup secret exchangeable for a session.
class PendingSignup < ApplicationRecord
  RESEND_WINDOW = 24.hours
  MAX_EMAILS_PER_ATTEMPT = 3
  MIN_EMAIL_INTERVAL = 60.seconds
  MAX_EMAILS_PER_MAILBOX = 3
  EMAIL_WINDOW = 1.hour
  # 24 h of sends, 24 h for the last link, then a week in which an old link still answers "expired".
  RETENTION = 9.days
  SECRET_FORMAT = /\A[A-Za-z0-9_-]{43}\z/
  SECRET_EXCHANGE_WINDOW = 1.hour

  has_secure_password validations: false

  belongs_to :user, optional: true
  has_many :tokens, class_name: "PendingSignupToken", inverse_of: :pending_signup

  validates :email, :normalized_email, :mailbox_key, :signup_secret_digest, :expires_at, presence: true
  validates :password_digest, presence: true, on: :create

  # The normalization of the user lookups (LOWER(email)), composed after downcasing as the mailbox key is, so both
  # Unicode spellings of an address share it.
  def self.normalize_email(email)
    User.normalize_value_for(:email, email.to_s).to_s.downcase.unicode_normalize(:nfc)
  end

  def self.mailbox_key(email)
    Signups::ValidateEmailService.mailbox_key(email)
  end

  # The digest has_secure_password writes, so a confirmed attempt can hand it to its User.
  def self.digest_password(password)
    BCrypt::Password.create(password, cost: ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost)
  end

  def self.generate_signup_secret
    SecureRandom.urlsafe_base64(32)
  end

  def self.digest_signup_secret(secret)
    OpenSSL::Digest::SHA256.hexdigest(secret)
  end

  def self.for_signup_secret(secret)
    find_by(signup_secret_digest: digest_signup_secret(secret)) if SECRET_FORMAT.match?(secret.to_s)
  end

  # Emails sent to a mailbox in the last hour, across its attempts. Attempts older than the resend window plus an hour
  # cannot have sent any.
  def self.mailbox_sends(mailbox_key, now)
    window_start = now - EMAIL_WINDOW

    where(mailbox_key:, created_at: (now - RESEND_WINDOW - EMAIL_WINDOW)..)
      .pluck(:emails_sent_at).flatten.select { it > window_start }.sort
  end

  # The refusal of a send to the mailbox (:limit_reached, :too_soon or nil) and the seconds before one is allowed,
  # from one read of its sends.
  def self.mailbox_send_state(mailbox_key, now)
    sends = mailbox_sends(mailbox_key, now)

    refusal = if sends.size >= MAX_EMAILS_PER_MAILBOX
      :limit_reached
    elsif sends.last&.after?(now - MIN_EMAIL_INTERVAL)
      :too_soon
    end
    # The minute rule, and the hour rule once 3 emails are in it.
    next_send_at = [
      (sends.last + MIN_EMAIL_INTERVAL if sends.any?),
      (sends[-MAX_EMAILS_PER_MAILBOX] + EMAIL_WINDOW if sends.size >= MAX_EMAILS_PER_MAILBOX)
    ].compact.max

    [refusal, next_send_at ? [(next_send_at - now).ceil, 0].max : 0]
  end

  def signup_secret_matches?(secret)
    SECRET_FORMAT.match?(secret.to_s) &&
      ActiveSupport::SecurityUtils.secure_compare(signup_secret_digest, self.class.digest_signup_secret(secret))
  end

  # Matches the LOWER(email) user lookups, so a case variant counts as the same account.
  def email_registered?
    User.where("LOWER(email) = ?", normalized_email).exists?
  end

  def verified?
    verified_at.present?
  end

  def closed?
    closed_at.present?
  end

  def sending_open?(now)
    now < expires_at && emails_sent_at.size < MAX_EMAILS_PER_ATTEMPT
  end

  def record_email_send(now)
    self.emails_sent_at += [now]
  end

  # Counts the other emails to the mailbox too, so a 0 means a resend goes out now; nil once it cannot send more,
  # including when the wait would end after the attempt's window. The attempt's own sends are among its mailbox's.
  def resend_available_in_seconds(now)
    if sending_open?(now)
      _refusal, delay = self.class.mailbox_send_state(mailbox_key, now)
      delay if wait_ends_in_window?(now, delay)
    end
  end

  # A send allowed only after the attempt's window never happens: the 429's retryAfterSeconds and the status's
  # resendAvailableInSeconds both read the attempt as exhausted then.
  def wait_ends_in_window?(now, wait)
    now + wait < expires_at
  end

  def resend_limit_reached?
    emails_sent_at.size >= MAX_EMAILS_PER_ATTEMPT
  end
end

# == Schema Information
#
# Table name: pending_signups
# Database name: primary
#
#  id                         :uuid             not null, primary key
#  closed_at                  :datetime
#  email                      :string           not null
#  emails_sent_at             :datetime         default([]), not null, is an Array
#  expires_at                 :datetime         not null
#  mailbox_key                :string           not null
#  normalized_email           :string           not null
#  password_digest            :string
#  signup_secret_digest       :string           not null
#  signup_secret_exchanged_at :datetime
#  verified_at                :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  user_id                    :uuid
#
# Indexes
#
#  index_pending_signups_on_created_at                  (created_at)
#  index_pending_signups_on_mailbox_key_and_created_at  (mailbox_key,created_at)
#  index_pending_signups_on_normalized_email            (normalized_email)
#  index_pending_signups_on_open_expires_at             (expires_at) WHERE ((verified_at IS NULL) AND (closed_at IS NULL))
#  index_pending_signups_on_signup_secret_digest        (signup_secret_digest) UNIQUE
#  index_pending_signups_on_user_id                     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
