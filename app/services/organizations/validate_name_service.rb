# frozen_string_literal: true

module Organizations
  # The rules on an organization name typed at self-serve signup: required, at most 100 characters, and no link, so
  # the name shown in emails and invites cannot carry one.
  class ValidateNameService < BaseService
    Result = BaseResult[:name]

    NAME_MAX_LENGTH = 100
    URL_SCHEME = %r{[a-z][a-z0-9+.-]*://}
    WWW = /(?<![\p{L}\p{N}])www\./
    IPV4 = /(?<![\d.])\d{1,3}(?:\.\d{1,3}){3}(?!\.?\d)/
    DOTTED_TOKEN = /[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+/
    # Ideographic and full-width full stops read as dots.
    DOT_LOOKALIKES = "。．｡"
    # Zero-width non-joiner and joiner: invisible, but part of Persian, Urdu and Indic spellings.
    JOINERS = /[\u200C\u200D]/
    INVISIBLE = /(?![\u200C\u200D])\p{Default_Ignorable_Code_Point}/

    def initialize(name:)
      @name = name
      super
    end

    def call
      normalized = normalize(name)

      if normalized.gsub(JOINERS, "").strip.empty?
        result.single_validation_failure!(field: :name, error_code: "value_is_mandatory")
      elsif normalized.length > NAME_MAX_LENGTH
        result.single_validation_failure!(field: :name, error_code: "value_is_too_long",
          meta: {max_length: NAME_MAX_LENGTH})
      elsif contains_link?(normalized)
        result.single_validation_failure!(field: :name, error_code: "value_contains_link")
      else
        result.name = normalized
        result
      end
    end

    private

    attr_reader :name

    # Kept as typed (no NFKC), without invisible characters other than the joiners, without control characters, with
    # spaces collapsed.
    def normalize(value)
      value.to_s.scrub("")
        .gsub(INVISIBLE, "")
        .gsub(/(?![[:space:]])\p{Cc}/, "")
        .gsub(/[[:space:]]+/, " ")
        .strip
    end

    # Every invisible character is dropped here, so a joiner cannot hide a link.
    def contains_link?(value)
      text = value.gsub(JOINERS, "").unicode_normalize(:nfkc).downcase.tr(DOT_LOOKALIKES, "...")
      return true if URL_SCHEME.match?(text) || WWW.match?(text) || IPV4.match?(text)

      text.scan(DOTTED_TOKEN).any? { PublicSuffix.valid?(it.delete_prefix("-"), default_rule: nil) }
    end
  end
end
