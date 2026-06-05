# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::QuoteVersions::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:organization).of_type("Organization!")
    expect(subject).to have_field(:quote).of_type("Quote!")
    expect(subject).to have_field(:approved_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:billing_items).of_type("JSON")
    expect(subject).to have_field(:content).of_type("String")
    expect(subject).to have_field(:mention_variables).of_type("JSON!")
    expect(subject).to have_field(:share_token).of_type("String")
    expect(subject).to have_field(:status).of_type("StatusEnum!")
    expect(subject).to have_field(:version).of_type("Int!")
    expect(subject).to have_field(:void_reason).of_type("VoidReasonEnum")
    expect(subject).to have_field(:voided_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:currency).of_type("String")
    expect(subject).to have_field(:start_date).of_type("ISO8601Date")
    expect(subject).to have_field(:end_date).of_type("ISO8601Date")
  end

  describe "#mention_variables" do
    let(:required_permission) { "quotes:view" }
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:customer) { create(:customer, organization:, name: "Mistral AI") }
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
        expect(execute).to include("customer_name" => "Mistral AI")
      end
    end

    context "when the version is approved" do
      before do
        create(:quote_version, :approved, quote:, organization:, mention_variables: {"customer_name" => "Snapshot AI"})
      end

      it "returns the persisted snapshot, ignoring later changes" do
        customer.update!(name: "Renamed AI")

        expect(execute).to eq("customer_name" => "Snapshot AI")
      end
    end
  end
end
