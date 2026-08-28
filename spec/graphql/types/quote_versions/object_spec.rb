# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::QuoteVersions::Object do
  subject { described_class }

  let_it_be(:user) { create_default(:user) }
  let_it_be(:organization) { create_default(:organization) }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:organization).of_type("Organization!")
    expect(subject).to have_field(:quote).of_type("Quote!")
    expect(subject).to have_field(:approved_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:billing_entity_id).of_type("ID")
    expect(subject).to have_field(:billing_items).of_type("JSON")
    expect(subject).to have_field(:content).of_type("String")
    expect(subject).to have_field(:mention_variables).of_type("JSON!")
    expect(subject).to have_field(:order_form).of_type("OrderForm")
    expect(subject).to have_field(:status).of_type("StatusEnum!")
    expect(subject).to have_field(:version).of_type("Int!")
    expect(subject).to have_field(:void_reason).of_type("VoidReasonEnum")
    expect(subject).to have_field(:voided_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:currency).of_type("CurrencyEnum")
  end

  describe "#mention_variables" do
    let(:required_permission) { "quotes:view" }
    let(:quote) { create(:quote, organization:, customer:) }
    let(:query) do
      <<~GQL
        query($quoteId: ID!) {
          quote(id: $quoteId) {
            currentVersion { mentionVariables }
          }
        }
      GQL
    end

    let_it_be(:membership) { create_default(:membership) }
    let_it_be(:customer) do
      create_default(:customer, organization:, name: "Hooli", legal_name: "Hooli Inc", firstname: "Gavin", lastname: "Belson")
    end

    def execute
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {quoteId: quote.id}
      ).dig("data", "quote", "currentVersion", "mentionVariables")
    end

    context "when the version is a draft" do
      before { create(:quote_version, quote:, organization:) }

      it "computes the variables live" do
        expect(execute).to include("customer_name" => "Hooli Inc - Gavin Belson")
      end
    end

    context "when the version is approved" do
      before do
        create(:quote_version, :approved, quote:, organization:, mention_variables: {"customer_name" => "Pied Piper"})
      end

      it "returns the persisted snapshot, ignoring later changes" do
        customer.update!(name: "Aviato")

        expect(execute).to eq("customer_name" => "Pied Piper")
      end
    end

    context "when the approved snapshot holds locale-sensitive variables" do
      let_it_be(:customer) { create_default(:customer, organization:, name: "Hooli", document_locale: "en") }

      before do
        create(
          :quote_version,
          :approved,
          quote:,
          organization:,
          mention_variables: {"commercial_terms_payment_terms" => 30, "commercial_terms_start_date" => "2026-04-01"}
        )
      end

      it "localizes the frozen snapshot in the customer's current locale" do
        expect(execute).to eq(
          "commercial_terms_payment_terms" => "Net 30",
          "commercial_terms_start_date" => "Apr 01, 2026"
        )
      end

      it "follows the customer's current locale" do
        customer.update!(document_locale: "fr")

        expect(execute).to eq(
          "commercial_terms_payment_terms" => "Net 30",
          "commercial_terms_start_date" => "1 avr. 2026"
        )
      end
    end
  end
end
