# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::CreditNotes::CreatedService do
  subject(:webhook_service) { described_class.new(object: credit_note) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:credit_note) { create(:credit_note, customer:, invoice:) }

  describe ".call" do
    it_behaves_like "creates webhook", "credit_note.created", "credit_note", {"customer" => Hash, "items" => []}
  end
end
