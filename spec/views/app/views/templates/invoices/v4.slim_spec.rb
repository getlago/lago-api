# frozen_string_literal: true

require "rails_helper"

RSpec.describe "invoices/v4/_credit.slim", type: :view do
  subject(:rendered_template) do
    html = Slim::Template.new(template, 1, pretty: true).render(invoice)
    HtmlBeautifier.beautify(html, stop_on_errors: true)
  end

  let(:template) { Rails.root.join("app/views/templates/invoices/v4.slim") }
  let(:invoice) do
    build_stubbed(
      :invoice,
      :credit,
      organization: organization,
      billing_entity: billing_entity,
      customer: customer,
      number: "LAGO-202509-001",
      payment_due_date: Date.parse("2025-09-04"),
      issuing_date: Date.parse("2025-09-04"),
      total_amount_cents: 1050,
      currency: "USD",
      fees: [fee]
    )
  end
  # Static organization data for consistent rendering
  let(:organization) do
    build_stubbed(
      :organization,
      name: "ACME Corporation",
      default_currency: "USD",
      country: "US"
    )
  end

  # Static billing entity data for consistent rendering
  let(:billing_entity) do
    build_stubbed(
      :billing_entity,
      organization: organization,
      name: "ACME Corporation",
      email: "billing@acme.com",
      address_line1: "123 Business St",
      address_line2: "Suite 100",
      city: "San Francisco",
      state: "CA",
      zipcode: "94105",
      country: "US"
    )
  end
  # Static customer data
  let(:customer) do
    build_stubbed(
      :customer,
      organization: organization,
      firstname: nil,
      lastname: nil,
      name: "John Doe",
      legal_name: "John Doe",
      legal_number: "1234567890",
      external_id: "customer_123",
      email: "john.doe@example.com",
      address_line1: "456 Customer Ave",
      address_line2: "Apt 202",
      city: "New York",
      state: "NY",
      zipcode: "10001",
      country: "US",
      phone: "+1-555-123-4567"
    )
  end

  # Static wallet data
  let(:wallet) do
    build_stubbed(
      :wallet,
      customer: customer,
      name: wallet_name,
      balance_currency: "USD",
      rate_amount: BigDecimal("1.0")
    )
  end

  # Static wallet transaction data
  let(:wallet_transaction) do
    build_stubbed(
      :wallet_transaction,
      wallet: wallet,
      credit_amount: BigDecimal("10.50"),
      amount: BigDecimal("10.50")
    )
  end

  # Static fee data
  let(:fee) do
    build_stubbed(
      :fee,
      id: "87654321-0fed-cba9-8765-4321fedcba90",
      fee_type: :credit,
      invoiceable: wallet_transaction,
      amount_cents: 1050,
      amount_currency: "USD"
    )
  end

  let(:wallet_name) { "Premium Wallet" }

  before do
    # Set locale to ensure consistent translations
    I18n.locale = :en
  end

  def snapshot_name(metadata)
    description =
      if metadata[:description].empty?
        # we have an "it { is_expected.to be something }" block
        metadata[:scoped_id]
      else
        metadata[:description]
      end
    example_group =
      if metadata.key?(:example_group)
        metadata[:example_group]
      else
        metadata[:parent_example_group]
      end

    description = description.tr("/", "_").tr(" ", "_")
    if example_group
      [snapshot_name(example_group), description].join("/")
    else
      description
    end
  end

  def expect_to_match_snapshot
    snapshot_name = self.snapshot_name(RSpec.current_example.metadata)
    expect(rendered_template).to match_snapshot("#{snapshot_name}.html")
  end

  context "when invoice_type is credit" do
    context "when wallet has no name" do
      let(:wallet_name) { nil }

      it "renders correctly" do
        expect_to_match_snapshot
      end
    end

    context "when wallet has a name" do
      let(:wallet_name) { "Premium Wallet" }

      it "renders correctly" do
        expect_to_match_snapshot
      end
    end
  end
end
