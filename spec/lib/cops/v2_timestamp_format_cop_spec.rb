# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::V2TimestampFormatCop, :config do
  it "registers an offense when formatting with iso8601" do
    expect_offense(<<~RUBY)
      { name: model.name, ended: model.ended_at.iso8601 }
                                 ^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` and render dates with `format_date` instead of `iso8601`.
    RUBY
  end

  it "registers an offense when formatting with a safe navigation and a precision" do
    expect_offense(<<~RUBY)
      model.ended_at&.iso8601(6)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` and render dates with `format_date` instead of `iso8601`.
    RUBY
  end

  it "registers an offense when formatting with xmlschema" do
    expect_offense(<<~RUBY)
      model.created_at.xmlschema
      ^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` and render dates with `format_date` instead of `xmlschema`.
    RUBY
  end

  it "registers an offense when formatting with rfc3339" do
    expect_offense(<<~RUBY)
      model.effective_from.rfc3339
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` and render dates with `format_date` instead of `rfc3339`.
    RUBY
  end

  it "registers an offense when formatting with strftime" do
    expect_offense(<<~RUBY)
      model.effective_from.strftime("%F")
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` and render dates with `format_date` instead of `strftime`.
    RUBY
  end

  it "registers an offense for a raw datetime" do
    expect_offense(<<~RUBY)
      { ended_at: model.ended_at }
        ^^^^^^^^^^^^^^^^^^^^^^^^ Declare `ended_at` with `timestamps`.
    RUBY
  end

  it "registers both offenses for a datetime rendered with format_time" do
    expect_offense(<<~RUBY)
      { created_at: format_time(model.created_at) }
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` instead of rendering them with `format_time`.
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare `created_at` with `timestamps`.
    RUBY
  end

  it "registers an offense for format_time under another key" do
    expect_offense(<<~RUBY)
      { effective_from: format_time(model.effective_from) }
                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` instead of rendering them with `format_time`.
    RUBY
  end

  it "registers an offense for format_time assigned into a payload" do
    expect_offense(<<~RUBY)
      payload[:voided_at] = format_time(model.voided_at)
                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` instead of rendering them with `format_time`.
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
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare `started_at` with `timestamps`.
    RUBY
  end

  it "registers both offenses for a date rendered as a datetime" do
    expect_offense(<<~RUBY)
      { effective_date: format_time(model.effective_date) }
                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` instead of rendering them with `format_time`.
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Render `effective_date` with `format_date`.
    RUBY
  end

  it "registers both offenses for a pair formatted with iso8601" do
    expect_offense(<<~RUBY)
      { ended_at: model.ended_at.iso8601 }
                  ^^^^^^^^^^^^^^^^^^^^^^ Declare v2 datetimes with `timestamps` and render dates with `format_date` instead of `iso8601`.
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare `ended_at` with `timestamps`.
    RUBY
  end

  it "does not register an offense for a date rendered with format_date" do
    expect_no_offenses(<<~RUBY)
      { effective_date: format_date(model.effective_date) }
    RUBY
  end

  it "registers an offense for a raw datetime merged into a payload" do
    expect_offense(<<~RUBY)
      payload.merge(started_at: model.started_at)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare `started_at` with `timestamps`.
    RUBY
  end

  %w[deep_merge reverse_merge with_defaults].each do |method|
    it "registers an offense for a raw datetime passed to #{method}" do
      expect_offense(<<~RUBY, method:)
        payload.%{method}(started_at: model.started_at)
                _{method} ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Declare `started_at` with `timestamps`.
      RUBY
    end
  end

  it "registers an offense for a raw datetime in a nested hash" do
    expect_offense(<<~RUBY)
      { product: { ended_at: model.ended_at } }
                   ^^^^^^^^^^^^^^^^^^^^^^^^ Declare `ended_at` with `timestamps`.
    RUBY
  end

  it "does not register an offense for the arguments of a query" do
    expect_no_offenses(<<~RUBY)
      model.rates.where(deleted_at: nil).order({created_at: :desc}).find_by(effective_date: Date.current)
    RUBY
  end

  it "does not register an offense for a nested hash in the arguments of a query" do
    expect_no_offenses(<<~RUBY)
      model.rates.joins(:phases).where(phases: {deleted_at: nil, created_at: ..Time.current})
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
