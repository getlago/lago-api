# frozen_string_literal: true

module Signups
  # The only check of a self-serve signup email: one well-formed address on a company domain.
  class ValidateEmailService < BaseService
    Result = BaseResult[:email, :domain, :mailbox_key]

    MAX_INPUT_LENGTH = 512
    MAX_LENGTH = 254
    MAX_LOCAL_PART_LENGTH = 64
    MAX_DOMAIN_LENGTH = 253
    # Regex::EMAIL also takes quoted parts and the =? ?= % ! of encoded words and routing, which a mail library or
    # relay can turn into another recipient than the company mailbox the domain check saw.
    LOCAL_PART = /\A[\p{L}\p{M}\p{N}._+'-]+\z/

    # Most providers deliver user+tag@ to user@ (a convention, not a standard), so limits and locks count by mailbox.
    # Where + belongs to a separate address, they only get stricter: user lookups never use this key.
    def self.mailbox_key(address)
      address = EmailSanitizer.call(address.to_s.scrub).to_s.downcase
      local_part, at, domain = address.rpartition("@")
      return address if at.empty?

      base = local_part.split("+", 2).first
      base = local_part if base.blank?

      "#{base.unicode_normalize(:nfc)}@#{domain}"
    end

    def initialize(email:)
      @email = email.to_s
      super
    end

    def call
      # Before any regex: GraphQL variables have no size limit, and invalid UTF-8 would raise.
      return failure("invalid_email_format") if email.length > MAX_INPUT_LENGTH || !email.valid_encoding?

      address = User.normalize_value_for(:email, email)
      return failure("value_is_mandatory") if address.blank?
      return failure("invalid_email_format") unless address.match?(Regex::EMAIL) && address.count("@") == 1

      address = address.downcase
      local_part, _, domain = address.partition("@")
      return failure("invalid_email_format") unless well_formed?(address, local_part, domain)
      return failure("email_domain_not_allowed") if EmailDomainPolicy.refusal_reason(domain)

      result.email = address
      result.domain = domain
      result.mailbox_key = self.class.mailbox_key(address)
      result
    end

    private

    attr_reader :email

    # Regex::EMAIL also accepts unbounded lengths and numeric domains.
    def well_formed?(address, local_part, domain)
      plain_local_part = LOCAL_PART.match?(local_part)
      short_enough = address.bytesize <= MAX_LENGTH && local_part.bytesize <= MAX_LOCAL_PART_LENGTH
      hostname = domain.start_with?("[") || (domain.bytesize <= MAX_DOMAIN_LENGTH && EmailDomainPolicy::HOSTNAME.match?(domain))

      plain_local_part && short_enough && hostname
    end

    def failure(code)
      result.single_validation_failure!(field: :email, error_code: code)
    end
  end
end
