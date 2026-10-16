# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::V2TimestampFormatCop, :config do
  it "registers an offense when formatting with iso8601" do
    expect_offense(<<~RUBY)
      { name: model.name, ended: model.ended_at.iso8601 }
                                 ^^^^^^^^^^^^^^^^^^^^^^ Render v2 timestamps with `format_time` or `format_date` instead of `iso8601`.
    RUBY
  end

  it "registers an offense when formatting with a safe navigation and a precision" do
    expect_offense(<<~RUBY)
      model.ended_at&.iso8601(6)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^ Render v2 timestamps with `format_time` or `format_date` instead of `iso8601`.
    RUBY
  end

  it "registers an offense when formatting with xmlschema" do
    expect_offense(<<~RUBY)
      model.created_at.xmlschema
      ^^^^^^^^^^^^^^^^^^^^^^^^^^ Render v2 timestamps with `format_time` or `format_date` instead of `xmlschema`.
    RUBY
  end

  it "registers an offense when formatting with strftime" do
    expect_offense(<<~RUBY)
      model.effective_from.strftime("%F")
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Render v2 timestamps with `format_time` or `format_date` instead of `strftime`.
    RUBY
  end

  it "registers an offense for a raw datetime" do
    expect_offense(<<~RUBY)
      { created_at: model.created_at }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Render `created_at` with `format_time`.
    RUBY
  end

  it "registers an offense for a raw date under a string key" do
    expect_offense(<<~RUBY)
      { "billing_anchor_date" => model.billing_anchor_date }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Render `billing_anchor_date` with `format_date`.
    RUBY
  end

  it "registers an offense for a datetime rendered as a date" do
    expect_offense(<<~RUBY)
      { started_at: format_date(model.started_at) }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Render `started_at` with `format_time`.
    RUBY
  end

  it "registers an offense for a date rendered as a datetime" do
    expect_offense(<<~RUBY)
      { effective_date: format_time(model.effective_date) }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Render `effective_date` with `format_date`.
    RUBY
  end

  it "registers both offenses for a pair formatted with iso8601" do
    expect_offense(<<~RUBY)
      { updated_at: model.updated_at.iso8601 }
                    ^^^^^^^^^^^^^^^^^^^^^^^^ Render v2 timestamps with `format_time` or `format_date` instead of `iso8601`.
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Render `updated_at` with `format_time`.
    RUBY
  end

  it "does not register an offense for the formatters" do
    expect_no_offenses(<<~RUBY)
      {
        effective_date: format_date(model.effective_date),
        next_billing_at: format_time(model.next_billing_at),
        effective_from: format_time(model.effective_from)
      }
    RUBY
  end

  it "registers an offense for a raw datetime merged into a payload" do
    expect_offense(<<~RUBY)
      payload.merge(started_at: model.started_at)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Render `started_at` with `format_time`.
    RUBY
  end

  it "does not register an offense for the arguments of a query" do
    expect_no_offenses(<<~RUBY)
      model.rates.where(deleted_at: nil).order({created_at: :desc}).find_by(effective_date: Date.current)
    RUBY
  end

  it "does not register an offense for a hash pattern" do
    expect_no_offenses(<<~RUBY)
      case payload
      in {created_at: String} then true
      end
    RUBY
  end

  it "does not register an offense for other keys" do
    expect_no_offenses(<<~RUBY)
      { name: model.name, format: model.format, update: model.update, **deleted_at_payload }
    RUBY
  end
end
