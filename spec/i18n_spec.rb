# frozen_string_literal: true

require "rails_helper"
require "i18n/tasks"

RSpec.describe I18n do
  let(:i18n) { I18n::Tasks::BaseTask.new }
  let(:missing_keys) { i18n.missing_keys }
  let(:unused_keys) { i18n.unused_keys }
  let(:inconsistent_interpolations) { i18n.inconsistent_interpolations }

  it "does not have missing translations" do
    missing_translations = i18n.missing_keys(types: [:diff])
    expect(missing_translations).to be_empty,
      "Missing #{missing_translations.leaves.count} translations, run `i18n-tasks missing -t diff' to show them"
  end

  # it 'does not have unused keys' do
  #   expect(unused_keys).to be_empty,
  #                          "#{unused_keys.leaves.count} unused i18n keys, run `i18n-tasks unused' to show them"
  # end

  it "files are normalized" do
    non_normalized = i18n.non_normalized_paths
    error_message = "The following files need to be normalized:\n" \
                    "#{non_normalized.map { |path| "  #{path}" }.join("\n")}\n" \
                    "Please run `i18n-tasks normalize' to fix"
    expect(non_normalized).to be_empty, error_message
  end

  it "uses each interpolation as many times as the base locale" do
    interpolations = ->(value) { value.is_a?(String) ? value.scan(/%\{(\w+)\}/).flatten.tally : {} }
    base = i18n.data[i18n.base_locale].leaves.to_h { |node| [node.full_key(root: false), interpolations.call(node.value)] }

    mismatches = (i18n.locales - [i18n.base_locale]).flat_map do |locale|
      i18n.data[locale].leaves.filter_map do |node|
        key = node.full_key(root: false)
        "#{locale}.#{key}" if base.key?(key) && base[key] != interpolations.call(node.value)
      end
    end

    expect(mismatches).to be_empty
  end

  it "does not have inconsistent interpolations" do
    error_message = "#{inconsistent_interpolations.leaves.count} i18n keys have inconsistent interpolations.\n" \
                    "Run `i18n-tasks check-consistent-interpolations' to show them"
    expect(inconsistent_interpolations).to be_empty, error_message
  end

  context "with the Slovak locale" do
    around { |example| described_class.with_locale(:sk) { example.run } }

    it "formats dates without English month names" do
      expect(described_class.l(Date.new(2026, 11, 16))).to eq("16. 11. 2026")
      expect(described_class.l(Date.new(2026, 1, 5))).to eq("5. 1. 2026")
    end

    it "uses Slovak month names in explicit date formats" do
      abbreviations = %w[Jan Feb Mar Apr Máj Jún Júl Aug Sep Okt Nov Dec]
      names = %w[Január Február Marec Apríl Máj Jún Júl August September Október November December]

      abbreviations.zip(names).each.with_index(1) do |(abbreviation, name), month|
        date = Date.new(2026, month, 17)

        expect(described_class.l(date, format: "%b")).to eq(abbreviation)
        expect(described_class.l(date, format: "%B")).to eq(name)
        expect(described_class.l(date, format: "%-d %b")).to eq("17 #{abbreviation}")
        expect(described_class.l(date, format: "%-d %b %Y")).to eq("17 #{abbreviation} 2026")
      end
    end

    it "uses Slovak day names in explicit date formats" do
      abbreviations = %w[Ne Po Ut St Št Pi So]
      names = %w[Nedeľa Pondelok Utorok Streda Štvrtok Piatok Sobota]

      abbreviations.zip(names).each.with_index do |(abbreviation, name), day|
        date = Date.new(2026, 11, 15) + day

        expect(described_class.l(date, format: "%a")).to eq(abbreviation)
        expect(described_class.l(date, format: "%A")).to eq(name)
      end
    end

    it "uses Slovak plural forms for quote durations" do
      {
        days: ["1 deň", "2 dni", "3 dni", "4 dni", "5 dní", "0 dní", "21 dní"],
        months: ["1 mesiac", "2 mesiace", "3 mesiace", "4 mesiace", "5 mesiacov", "0 mesiacov", "21 mesiacov"],
        years: ["1 rok", "2 roky", "3 roky", "4 roky", "5 rokov", "0 rokov", "21 rokov"]
      }.each do |unit, labels|
        [1, 2, 3, 4, 5, 0, 21].zip(labels).each do |count, label|
          expect(described_class.t("quote_version.mention_variables.term_duration.#{unit}", count:)).to eq(label)
        end
      end
    end

    it "uses Slovak plural forms for invoice transactions" do
      {1 => "1 transakciu", 2 => "2 transakcie", 3 => "3 transakcie", 4 => "4 transakcie", 5 => "5 transakcií", 0 => "0 transakcií"}.each do |count, label|
        expect(described_class.t("invoice.percentage.free_units_per_transaction", count:)).to eq("Bezplatné jednotky na #{label}")
      end
    end

    it "uses the other plural form for fractional counts" do
      expect(described_class.t("invoice.percentage.free_units_per_transaction", count: 2.5)).to eq("Bezplatné jednotky na 2.5 transakcií")
    end

    it "uses Slovak plural forms for payment terms" do
      {1 => "1 deň", 2 => "2 dni", 3 => "3 dni", 4 => "4 dni", 5 => "5 dní"}.each do |days, label|
        expect(described_class.t("invoice.payment_terms.net_end_of_month", count: days, days:)).to eq("Splatné #{label} po skončení mesiaca")
      end
      expect(described_class.t("invoice.payment_terms.net", count: 1, days: 1)).to eq("Splatné do 1 dňa")
      expect(described_class.t("invoice.payment_terms.net", count: 2, days: 2)).to eq("Splatné do 2 dní")
    end

    it "keeps API error codes unchanged" do
      expect(described_class.t("activerecord.errors.messages.blank")).to eq("value_is_mandatory")
      expect(described_class.t("activerecord.errors.messages.invalid")).to eq("value_is_invalid")
    end
  end
end
