# frozen_string_literal: true

require "rails_helper"

RSpec.describe ValidationMeta do
  describe ".check" do
    subject(:checked) { described_class.check(meta) }

    let(:meta) { {min: 1, max: 3, max_length: 255, max_items: 1000, allowed_values: %w[day month], provider_code: "stripe_eu"} }

    it { expect(checked).to eq(min: 1, max: 3, max_length: 255, max_items: 1000, allowed_values: %w[day month], provider_code: "stripe_eu") }

    context "with string keys" do
      let(:meta) { {"min" => 1, "allowed_values" => %w[day]} }

      it { expect(checked).to eq(min: 1, allowed_values: %w[day]) }
    end

    context "with nil values" do
      let(:meta) { {min: 1, max: nil} }

      it { expect(checked).to eq(min: 1) }
    end

    context "with symbols" do
      let(:meta) { {resource: :customer, allowed_values: %i[day month]} }

      it "checks them as the strings their JSON is" do
        expect(checked).to eq(resource: "customer", allowed_values: %w[day month])
      end
    end

    context "without meta" do
      let(:meta) { nil }

      it { expect(checked).to eq({}) }
    end

    {
      {1 => 2} => "meta 1: 2",
      {count: 1} => "meta count: 1",
      {min: 1.5} => "meta min: 1.5",
      {max: BigDecimal("3")} => 'meta max: "3.0"',
      {value: 1} => "meta value: 1",
      {allowed_values: ["day", 1]} => 'meta allowed_values: ["day", 1]'
    }.each do |given, refusal|
      context "with #{given}" do
        let(:meta) { given }

        it { expect { checked }.to raise_error(ArgumentError, "#{refusal} is not a registered key and type") }
      end
    end

    context "when the environment is not local" do
      let(:meta) { {:min => 1, :max => 1.5, :count => 2, 1 => 2} }

      before do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Rails.logger).to receive(:warn)
        allow(Sentry).to receive(:capture_exception)
      end

      # A min without its max would read as a value without an upper bound.
      it "drops the whole meta and reports each bad key" do
        expect(checked).to eq({})
        expect(Rails.logger).to have_received(:warn).with("ValidationMeta: meta max: 1.5 is not a registered key and type")
        expect(Rails.logger).to have_received(:warn).exactly(3).times
        expect(Sentry).to have_received(:capture_exception).exactly(3).times
        expect(Sentry).to have_received(:capture_exception).with(an_object_having_attributes(message: "meta count: 2 is not a registered key and type"))
        expect(Sentry).to have_received(:capture_exception).with(an_object_having_attributes(message: "meta 1: 2 is not a registered key and type"))
      end
    end
  end
end
