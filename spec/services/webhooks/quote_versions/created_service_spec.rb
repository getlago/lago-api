# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::QuoteVersions::CreatedService do
  subject(:webhook_service) { described_class.new(object: quote_version) }

  let(:organization) { create(:organization, feature_flags: [:order_forms]) }
  let(:quote_version) { create(:quote_version, organization:) }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "quote_version.created", "quote_version", {
      "lago_id" => String,
      "quote_id" => String,
      "version" => Integer,
      "number" => String,
      "status" => String,
      "void_reason" => NilClass,
      "voided_at" => NilClass,
      "approved_at" => NilClass,
      "created_at" => String
    }
  end
end
