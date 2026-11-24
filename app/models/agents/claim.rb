# frozen_string_literal: true

module Agents
  # A person claiming an agent: a code the agent hands to its owner, then the e-mail the owner verifies. Only digests
  # of the code and of the verification code are stored; the e-mail is kept encrypted until it reaches the customer.
  class Claim < ApplicationRecord
    self.table_name = "agent_claims"

    STATUSES = {issued: "issued", started: "started", verified: "verified"}.freeze
    PUBLIC_STATUSES = {"issued" => "unclaimed", "started" => "pending", "verified" => "claimed"}.freeze
    # No 0, O, 1 or I: the owner types the code.
    CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    CODE_LENGTH = 8
    CODE_GROUP_SIZE = 4
    VERIFICATION_CODE_LENGTH = 6
    VERIFICATION_TTL = 10.minutes
    GMAIL_DOMAINS = %w[gmail.com googlemail.com].freeze

    belongs_to :organization
    belongs_to :registration, class_name: "Agents::Registration"

    encrypts :email

    enum :status, STATUSES, validate: true

    validates :code_hash, presence: true

    scope :live, -> { where(status: %w[issued started]) }

    def self.digest(value)
      OpenSSL::Digest::SHA256.hexdigest(value)
    end

    # The owner's mailbox under a key: an address has none of the entropy of a code, so a plain digest would give the
    # owners away to anyone holding the table.
    def self.mailbox_digest(email)
      key = Rails.application.key_generator.generate_key("agents/claims/mailbox")
      OpenSSL::HMAC.hexdigest("SHA256", key, mailbox(email))
    end

    # One string per inbox: the signup mails' key (case, +tag), plus what Gmail ignores, dots in the local part and
    # the googlemail domain.
    def self.mailbox(email)
      key = Signups::ValidateEmailService.mailbox_key(email)
      local, domain = key.split("@", 2)

      GMAIL_DOMAINS.include?(domain) ? "#{local.delete(".")}@gmail.com" : key
    end

    # What the owner types: case and separators do not matter.
    def self.normalize_code(input)
      input.to_s.gsub(/[^A-Za-z0-9]/, "").upcase
    end

    def self.for_code(input)
      code = normalize_code(input)
      find_by(code_hash: digest(code)) if code.length == CODE_LENGTH
    end

    def self.generate_code
      Array.new(CODE_LENGTH) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.length)] }.join
    end

    def self.format_code(code)
      code.scan(/.{1,#{CODE_GROUP_SIZE}}/).join("-")
    end

    def self.generate_verification_code
      SecureRandom.random_number(10**VERIFICATION_CODE_LENGTH).to_s.rjust(VERIFICATION_CODE_LENGTH, "0")
    end

    def public_status
      PUBLIC_STATUSES.fetch(status)
    end

    # Expiry is derived from the time, never stored as a status.
    def verification_expired?(now = Time.current)
      verification_expires_at.present? && verification_expires_at <= now
    end
  end
end

# == Schema Information
#
# Table name: agent_claims
# Database name: primary
#
#  id                      :uuid             not null, primary key
#  code_hash               :string           not null
#  email                   :string
#  email_hash              :string
#  status                  :enum             default("issued"), not null
#  verification_code_hash  :string
#  verification_expires_at :datetime
#  verified_at             :datetime
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  organization_id         :uuid             not null
#  registration_id         :uuid             not null
#
# Indexes
#
#  index_agent_claims_on_code_hash        (code_hash) UNIQUE
#  index_agent_claims_on_organization_id  (organization_id)
#  index_agent_claims_on_registration_id  (registration_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (registration_id => agent_registrations.id) ON DELETE => cascade
#
