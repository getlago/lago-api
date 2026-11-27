# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::UpdateAllUpdatedAtCop, :config do
  it "registers an offense and adds updated_at to a hash without it" do
    expect_offense(<<~RUBY)
      invoices.update_all(status: :finalized)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Set `updated_at` in `update_all`, as it skips callbacks.
    RUBY

    expect_correction(<<~RUBY)
      invoices.update_all(status: :finalized, updated_at: Time.current)
    RUBY
  end

  it "registers an offense on a safe navigation call" do
    expect_offense(<<~RUBY)
      invoices&.update_all(status: :finalized)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Set `updated_at` in `update_all`, as it skips callbacks.
    RUBY

    expect_correction(<<~RUBY)
      invoices&.update_all(status: :finalized, updated_at: Time.current)
    RUBY
  end

  it "adds updated_at on its own line to a multi-line hash" do
    expect_offense(<<~RUBY)
      invoices.update_all(
      ^^^^^^^^^^^^^^^^^^^^ Set `updated_at` in `update_all`, as it skips callbacks.
        status: :finalized,
        ready_to_be_refreshed: false
      )
    RUBY

    expect_correction(<<~RUBY)
      invoices.update_all(
        status: :finalized,
        ready_to_be_refreshed: false,
        updated_at: Time.current
      )
    RUBY
  end

  it "adds updated_at inside the braces of a hash literal" do
    expect_offense(<<~RUBY)
      invoices.update_all({status: :finalized})
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Set `updated_at` in `update_all`, as it skips callbacks.
    RUBY

    expect_correction(<<~RUBY)
      invoices.update_all({status: :finalized, updated_at: Time.current})
    RUBY
  end

  it "registers an offense on an SQL string without updated_at" do
    expect_offense(<<~RUBY)
      invoices.update_all("search_terms = \#{SQL}")
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Set `updated_at` in `update_all`, as it skips callbacks.
    RUBY

    expect_no_corrections
  end

  it "registers an offense on an SQL array without updated_at" do
    expect_offense(<<~RUBY)
      invoices.update_all(["total = ?", 10])
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Set `updated_at` in `update_all`, as it skips callbacks.
    RUBY

    expect_no_corrections
  end

  it "registers an offense on an SQL heredoc without updated_at" do
    expect_offense(<<~RUBY)
      invoices.update_all(<<~SQL)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Set `updated_at` in `update_all`, as it skips callbacks.
        status = 1
      SQL
    RUBY

    expect_no_corrections
  end

  it "does not register an offense when an SQL heredoc sets updated_at" do
    expect_no_offenses(<<~RUBY)
      invoices.update_all(<<~SQL)
        status = 1, updated_at = NOW()
      SQL
      invoices.update_all([<<~SQL, Time.current])
        status = 1, updated_at = ?
      SQL
    RUBY
  end

  it "does not register an offense when the hash sets updated_at" do
    expect_no_offenses(<<~RUBY)
      invoices.update_all(status: :finalized, updated_at: Time.current)
      invoices.update_all("status" => "finalized", "updated_at" => Time.current)
    RUBY
  end

  it "does not register an offense when the SQL sets updated_at" do
    expect_no_offenses(<<~RUBY)
      invoices.update_all("total = 10, updated_at = NOW()")
      invoices.update_all(["total = ?, updated_at = ?", 10, Time.current])
    RUBY
  end

  it "does not register an offense when the attributes cannot be read" do
    expect_no_offenses(<<~RUBY)
      invoices.update_all(attributes)
      invoices.update_all(**attributes, status: :finalized)
      invoices.update_all
    RUBY
  end
end
