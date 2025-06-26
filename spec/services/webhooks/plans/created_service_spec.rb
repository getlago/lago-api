# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Plans::CreatedService do
  subject(:webhook_service) { described_class.new(object: plan) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "plan.created", "plan"
  end
end
