# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhooksQuery, type: :query do
  subject(:webhook_query) { described_class.new(webhook_endpoint:) }

  let(:organization) { webhook_endpoint.organization.reload }
  let(:webhook_endpoint) { create(:webhook_endpoint) }
  let(:webhook_succeeded) { create(:webhook, :succeeded, webhook_endpoint:) }
  let(:webhook_failed) { create(:webhook, :failed, webhook_endpoint:) }
  let(:webhook_other_type) { create(:webhook, :succeeded, webhook_endpoint:, webhook_type: "invoice.generated") }

  before do
    webhook_succeeded
    webhook_failed
    webhook_other_type
  end

  it "returns all webhooks" do
    result = webhook_query.call(
      search_term: nil,
      page: 1,
      limit: 10
    )

    returned_ids = result.webhooks.pluck(:id)

    aggregate_failures do
      expect(result.webhooks.count).to eq(3)
      expect(returned_ids).to include(webhook_succeeded.id)
      expect(returned_ids).to include(webhook_failed.id)
      expect(returned_ids).to include(webhook_other_type.id)
    end
  end

  context "when search for /generated/ term" do
    it "returns only one webhook" do
      result = webhook_query.call(
        search_term: "generated",
        page: 1,
        limit: 10
      )

      returned_ids = result.webhooks.pluck(:id)

      aggregate_failures do
        expect(result.webhooks.count).to eq(1)
        expect(returned_ids).to include(webhook_other_type.id)
      end
    end
  end

  context "when search for /created/ term and filtering by status" do
    it "returns only one webhook" do
      result = webhook_query.call(
        search_term: "created",
        page: 1,
        limit: 10,
        status: "succeeded"
      )

      returned_ids = result.webhooks.pluck(:id)

      aggregate_failures do
        expect(result.webhooks.count).to eq(1)
        expect(returned_ids).to include(webhook_succeeded.id)
      end
    end
  end
end
