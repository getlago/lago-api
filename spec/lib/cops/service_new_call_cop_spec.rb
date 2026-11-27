# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::ServiceNewCallCop, :config do
  let(:cop_config) { {"AllowedReceivers" => ["Subscriptions::TerminatedDatesService"]} }

  it "registers an offense and calls the service on its class" do
    expect_offense(<<~RUBY)
      Invoices::RetryService.new(invoice: invoice).call
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Invoices::RetryService.call(...)` instead of `Invoices::RetryService.new(...).call`, which skips the middlewares.
    RUBY

    expect_correction(<<~RUBY)
      Invoices::RetryService.call(invoice: invoice)
    RUBY
  end

  it "registers an offense on call! and keeps the bang" do
    expect_offense(<<~RUBY)
      ::Credits::CreditNoteService.new(invoice: invoice).call!
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `::Credits::CreditNoteService.call!(...)` instead of `::Credits::CreditNoteService.new(...).call!`, which skips the middlewares.
    RUBY

    expect_correction(<<~RUBY)
      ::Credits::CreditNoteService.call!(invoice: invoice)
    RUBY
  end

  it "keeps the layout of multi-line arguments" do
    expect_offense(<<~RUBY)
      Invoices::UpdateService.new(
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Invoices::UpdateService.call(...)` instead of `Invoices::UpdateService.new(...).call`, which skips the middlewares.
        invoice: invoice,
        params: params
      ).call
    RUBY

    expect_correction(<<~RUBY)
      Invoices::UpdateService.call(
        invoice: invoice,
        params: params
      )
    RUBY
  end

  it "registers an offense on a service without arguments" do
    expect_offense(<<~RUBY)
      Events::PurgeService.new.call
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Events::PurgeService.call(...)` instead of `Events::PurgeService.new(...).call`, which skips the middlewares.
    RUBY

    expect_correction(<<~RUBY)
      Events::PurgeService.call
    RUBY
  end

  it "registers an offense on described_class in a service spec" do
    expect_offense(<<~RUBY, "spec/services/invoices/retry_service_spec.rb")
      described_class.new(invoice: invoice).call
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `described_class.call(...)` instead of `described_class.new(...).call`, which skips the middlewares.
    RUBY

    expect_correction(<<~RUBY)
      described_class.call(invoice: invoice)
    RUBY
  end

  it "does not register an offense on described_class outside a service spec" do
    expect_no_offenses(<<~RUBY, "spec/contracts/queries/customers_query_filters_contract_spec.rb")
      described_class.new.call
    RUBY
  end

  it "does not register an offense when call takes arguments" do
    expect_no_offenses(<<~RUBY)
      Invoices::FinalizeBatchService.new(organization: organization).call(invoice_ids)
    RUBY
  end

  it "does not register an offense on a class that is not a service" do
    expect_no_offenses(<<~RUBY)
      ActiveRecord::Associations::Preloader.new(records: records, associations: associations).call
    RUBY
  end

  it "does not register an offense on an allowed receiver" do
    expect_no_offenses(<<~RUBY)
      Subscriptions::TerminatedDatesService.new(subscription: subscription).call
    RUBY
  end

  it "does not register an offense on a service called on its class" do
    expect_no_offenses(<<~RUBY)
      Invoices::RetryService.call(invoice: invoice)
    RUBY
  end
end
