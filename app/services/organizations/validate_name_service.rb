# frozen_string_literal: true

module Organizations
  # The rules on an organization name typed at self-serve signup: required, at most 100 characters, and no link, so
  # the name shown in emails and invites cannot carry one.
  class ValidateNameService < BaseService
    Result = BaseResult[:name]

    NAME_MAX_LENGTH = 100
    URL_SCHEME = %r{[a-z][a-z0-9+.-]*://}
    # Schemes that work without slashes.
    BARE_SCHEME = /(?<![\p{L}\p{N}])(?:javascript|vbscript|data|mailto|file):\S/
    WWW = /(?<![\p{L}\p{N}])www\./
    IPV4 = /(?<![\d.])\d{1,3}(?:\.\d{1,3}){3}(?!\.?\d)/
    DOTTED_TOKEN = /[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+/
    # Legal forms written after a dot (`Acme Co.Ltd`, `Muster GmbH & Co.KG`): some are also top-level domains, so a
    # dotted token loses them before the domain check.
    LEGAL_FORMS = %w[
      ab ag as bhd bv co corp gmbh inc kft kg kk lda llc llp lp ltd ltda nv oy plc pte pty pvt sa sarl sas sdn se sl
      spa sro srl ug
    ].to_set.freeze
    # Ideographic and full-width full stops read as dots.
    DOT_LOOKALIKES = "。．｡"
    # Zero-width non-joiner and joiner (part of Persian, Urdu and Indic spellings) and variation selectors (part of
    # emoji such as U+2764 U+FE0F): invisible, but kept.
    KEPT_INVISIBLE = /[\u200C\u200D\uFE00-\uFE0F\u{E0100}-\u{E01EF}]/
    INVISIBLE = /(?!#{KEPT_INVISIBLE})\p{Default_Ignorable_Code_Point}/

    def initialize(name:)
      @name = name
      super
    end

    def call
      normalized = normalize(name)

      if normalized.gsub(KEPT_INVISIBLE, "").strip.empty?
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

    # Kept as typed (no NFKC), without invisible characters other than the kept ones, without control characters, with
    # spaces collapsed.
    def normalize(value)
      value.to_s.scrub("")
        .gsub(INVISIBLE, "")
        .gsub(/(?![[:space:]])\p{Cc}/, "")
        .gsub(/[[:space:]]+/, " ")
        .strip
    end

    # Every invisible character is dropped here, so a kept one cannot hide a link.
    def contains_link?(value)
      text = value.gsub(KEPT_INVISIBLE, "").unicode_normalize(:nfkc).downcase.tr(DOT_LOOKALIKES, "...")
      return true if [URL_SCHEME, BARE_SCHEME, WWW, IPV4].any? { it.match?(text) }

      text.scan(DOTTED_TOKEN).any? { domain?(it.delete_prefix("-")) }
    end

    # `co.ltd` is checked as `co`, `acme.com.ltd` as `acme.com`.
    def domain?(token)
      labels = token.split(".")
      labels.pop while labels.size > 1 && trailing_legal_form?(labels)
      labels.size > 1 && PublicSuffix.valid?(labels.join("."), default_rule: nil)
    end

    # A two-letter legal form is also a country code: it goes only after another legal form (`Co.KG`), so a bare
    # domain on it (`acme.co`, `shop.se`) stays a domain.
    def trailing_legal_form?(labels)
      form = labels.last
      LEGAL_FORMS.include?(form) && (form.length > 2 || LEGAL_FORMS.include?(labels[-2]))
    end
  end
end
