# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::ValidateMethodPrefixCop, :config do
  it "registers an offense for a method without the prefix" do
    expect_offense(<<~RUBY)
      validate :currency_matches_plan, if: :currency_changed?
               ^^^^^^^^^^^^^^^^^^^^^^ Name a method passed to `validate` with the `validate_` prefix (`validate_currency_matches_plan`).
    RUBY
  end

  it "registers an offense for each method without the prefix" do
    expect_offense(<<~RUBY)
      validate :validate_https_urls, :stripe_provider_exists
                                     ^^^^^^^^^^^^^^^^^^^^^^^ Name a method passed to `validate` with the `validate_` prefix (`validate_stripe_provider_exists`).
    RUBY
  end

  it "accepts a method with the prefix" do
    expect_no_offenses(<<~RUBY)
      validate :validate_currency_matches_plan, on: :create
    RUBY
  end

  it "accepts a block" do
    expect_no_offenses(<<~RUBY)
      validate { errors.add(:base, :invalid) }
    RUBY
  end

  it "accepts a call with a receiver" do
    expect_no_offenses(<<~RUBY)
      contract.validate(:strict)
    RUBY
  end
end
