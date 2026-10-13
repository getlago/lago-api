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
end
