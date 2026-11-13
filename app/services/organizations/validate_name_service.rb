# frozen_string_literal: true

module Organizations
  # The rules on an organization name typed at self-serve signup: required, at most 100 characters, and no link, so
  # the name shown in emails and invites cannot carry one. `allow_links` keeps the other rules for a name typed by an
  # admin, who may create an organization named after its domain.
  class ValidateNameService < BaseService
    Result = BaseResult[:name]

    NAME_MAX_LENGTH = 100
    URL_SCHEME = %r{[a-z][a-z0-9+.-]*://}
    # Schemes that work without slashes.
    BARE_SCHEME = /(?<![\p{L}\p{N}])(?:javascript|vbscript|data|mailto|file|tel|sms|callto|facetime):\S/
    WWW = /(?<![\p{L}\p{N}])www\./
    IPV4 = /(?<![\d.])\d{1,3}(?:\.\d{1,3}){3}(?!\.?\d)/
    # Combining marks are part of a label: Indic top-level domains (`இந்தியா`, `भारत`) are written with them.
    DOTTED_TOKEN = /[\p{L}\p{M}\p{N}-]+(?:\.[\p{L}\p{M}\p{N}-]+)+/
    # Legal forms written with a dot (`Acme Co.Ltd`, `Muster GmbH & Co.KG`). Only these whole tokens are spared: a
    # legal form after any other label (`evil.ltd`, `evil.ltd.co`) is a domain on a real top-level domain.
    DOTTED_LEGAL_FORMS = %w[co.kg co.kk co.ltd pte.ltd pty.ltd pvt.ltd sdn.bhd].to_set.freeze
    # Ideographic and full-width full stops read as dots.
    DOT_LOOKALIKES = "。．｡"
    # Zero-width non-joiner and joiner (part of Persian, Urdu and Indic spellings) and variation selectors (part of
    # emoji such as U+2764 U+FE0F): invisible, but kept.
    KEPT_INVISIBLE = /[\u200C\u200D\uFE00-\uFE0F\u{E0100}-\u{E01EF}]/
    INVISIBLE = /(?!#{KEPT_INVISIBLE})\p{Default_Ignorable_Code_Point}/

    def initialize(name:, allow_links: false)
      @name = name
      @allow_links = allow_links
      super
    end

    def call
      normalized = normalize(name)

      if normalized.gsub(KEPT_INVISIBLE, "").strip.empty?
        result.single_validation_failure!(field: :name, error_code: "value_is_mandatory")
      elsif normalized.length > NAME_MAX_LENGTH
        result.single_validation_failure!(field: :name, error_code: "value_is_too_long",
          meta: {max_length: NAME_MAX_LENGTH})
      elsif !allow_links && contains_link?(normalized)
        result.single_validation_failure!(field: :name, error_code: "value_contains_link")
      else
        result.name = normalized
        result
      end
    end

    private

    attr_reader :name, :allow_links

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

      text.scan(DOTTED_TOKEN).any? { domain?(it) }
    end

    # A label starting with a hyphen cannot continue a host, so the token is cut before it and each part is checked
    # without its leading hyphens (`Dr.-Ing.` holds no domain, `Acme.-evil.com` holds `evil.com`).
    def domain?(token)
      token.split(/\.(?=-)/).any? { host?(it.sub(/\A-+/, "")) }
    end

    # The last label loses its trailing hyphens (`evil.com-` is linked as `evil.com`) and is checked cut at a hyphen
    # too (`evil.com-x`). Any Punycode label (`xn--p1ai`) counts as a domain.
    def host?(part)
      labels = part.split(".").reject(&:empty?)
      return false if labels.size < 2

      labels[-1] = labels.last.sub(/-+\z/, "")
      return true if labels.any? { it.start_with?("xn--") }

      cut = labels[...-1] + [labels.last.split("-").first]
      [labels, cut].map { it.join(".") }.any? do |host|
        !DOTTED_LEGAL_FORMS.include?(host) && PublicSuffix.valid?(host, default_rule: nil)
      end
    end
  end
end
