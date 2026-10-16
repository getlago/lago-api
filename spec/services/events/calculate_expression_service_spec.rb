# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::CalculateExpressionService do
  describe "#call" do
    subject(:service_call) { described_class.new(organization: organization, event: event).call }

    let(:organization) { create(:organization) }
    let(:event) { create(:event, organization: organization, timestamp: Time.current, code: code, properties: properties) }
    let(:code) { "test_code" }
    let(:properties) { {"left" => "1", "right" => "2"} }
    let(:expression) { nil }
    let(:field_name) { "result" }
    let(:billable_metric) { create(:sum_billable_metric, organization: organization, code: code, field_name: field_name, expression: expression) }

    before do
      billable_metric
    end

    context "when there is no expression configured" do
      it "does not modify the event properties" do
        expect(service_call).to be_success
        expect(service_call.event.properties).to eq(properties)
      end
    end

    context "when an expression is configured for the billable metric" do
      let(:expression) { "event.properties.left + event.properties.right" }

      it "evaluates the expression and updates the event properties" do
        expect(service_call).to be_success
        expect(service_call.event.properties[field_name]).to eq(3)
      end
    end

    context "when the expression divides by a property equal to zero" do
      let(:expression) { "event.properties.left / event.properties.right" }
      let(:properties) { {"left" => "1", "right" => "0"} }

      it "returns a failure instead of raising" do
        expect(service_call).not_to be_success
        expect(service_call.error.code.to_s).to eq("expression_evaluation_failed")
      end
    end
  end
end
