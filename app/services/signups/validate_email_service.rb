# frozen_string_literal: true

module Signups
  # The only check of a self-serve signup email: one well-formed address on a company domain.
  class ValidateEmailService < BaseService
    Result = BaseResult[:email, :domain, :mailbox_key]

    MAX_INPUT_LENGTH = 512
    # The encodings every later step handles; US-ASCII is what nil.to_s gives.
    INPUT_ENCODINGS = [Encoding::UTF_8, Encoding::US_ASCII].freeze
    MAX_LENGTH = 254
    MAX_LOCAL_PART_LENGTH = 64
    MAX_DOMAIN_LENGTH = 253
    # Regex::EMAIL also takes quoted parts and the =? ?= % ! of encoded words and routing, which a mail library or
    # relay can turn into another recipient than the company mailbox the domain check saw.
    LOCAL_PART = /\A[\p{L}\p{M}\p{N}._+'-]+\z/

    # Most providers deliver user+tag@ to user@ (a convention, not a standard), so limits and locks count by mailbox.
    # Where + belongs to a separate address, they only get stricter: user lookups never use this key.
    def self.mailbox_key(address)
      # Never raises: the email lock calls it with addresses that were not validated (Okta, Entra ID, invites, Google).
      address = EmailSanitizer.call(to_utf8(address.to_s)).to_s.downcase
      local_part, at, domain = address.rpartition("@")
      return address if at.empty?

      base = local_part.split("+", 2).first
      base = local_part if base.blank?

      "#{base.unicode_normalize(:nfc)}@#{domain}"
    end

    # Bytes that cannot be decoded become U+FFFD, also in an encoding Ruby cannot convert from (UTF-7).
    def self.to_utf8(text)
      text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    rescue Encoding::ConverterNotFoundError
      text.b.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
    private_class_method :to_utf8

    def initialize(email:)
      @email = email.to_s
      super
    end

    def call
      # Before any regex: GraphQL variables have no size limit, and another encoding or invalid UTF-8 would raise.
      return failure("invalid_email_format") unless readable?(email)

      address = User.normalize_value_for(:email, email)
      return failure("value_is_mandatory") if address.blank?
      return failure("invalid_email_format") unless address.match?(Regex::EMAIL) && address.count("@") == 1

      # Composed after downcasing, as mailbox_key does: a capital and its mark can compose only once lowercased.
      address = address.downcase.unicode_normalize(:nfc)
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

    def readable?(input)
      input.length <= MAX_INPUT_LENGTH && INPUT_ENCODINGS.include?(input.encoding) && input.valid_encoding?
    end

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
