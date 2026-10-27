# frozen_string_literal: true

require "rails_helper"

RSpec.describe ValidationMeta do
  describe ".check" do
    subject(:checked) { described_class.check(meta) }

    let(:meta) { {min: 1, max: 3, allowed_values: %w[day month], provider_code: "stripe_eu"} }

    it { expect(checked).to eq(min: 1, max: 3, allowed_values: %w[day month], provider_code: "stripe_eu") }

    context "with string keys" do
      let(:meta) { {"min" => 1, "allowed_values" => %w[day]} }

      it { expect(checked).to eq(min: 1, allowed_values: %w[day]) }
    end

    context "with nil values" do
      let(:meta) { {min: 1, max: nil} }

      it { expect(checked).to eq(min: 1) }
    end

    context "without meta" do
      let(:meta) { nil }

      it { expect(checked).to eq({}) }
    end

    context "with a String instead of a Hash" do
      let(:meta) { "min" }

      it { expect { checked }.to raise_error(ArgumentError, "meta is not a Hash: String") }
    end

    context "with an Array instead of a Hash" do
      let(:meta) { [{min: 1}] }

      it { expect { checked }.to raise_error(ArgumentError, "meta is not a Hash: Array") }
    end

    context "with parameters" do
      let(:meta) { ActionController::Parameters.new(min: 1) }

      it { expect { checked }.to raise_error(ArgumentError, "meta is not a Hash: ActionController::Parameters") }
    end

    context "with an Integer key" do
      let(:meta) { {1 => 2} }

      it { expect { checked }.to raise_error(ArgumentError, "meta 1: 2 is not a registered key and type") }
    end

    context "with an unregistered key" do
      let(:meta) { {count: 1} }

      it { expect { checked }.to raise_error(ArgumentError, "meta count: 1 is not a registered key and type") }
    end

    context "with a Float" do
      let(:meta) { {min: 1.5} }

      it { expect { checked }.to raise_error(ArgumentError, "meta min: 1.5 is not a registered key and type") }
    end

    context "with a BigDecimal" do
      let(:meta) { {max: BigDecimal("3")} }

      it { expect { checked }.to raise_error(ArgumentError, "meta max: 0.3e1 is not a registered key and type") }
    end

    context "with an Integer where a String is declared" do
      let(:meta) { {value: 1} }

      it { expect { checked }.to raise_error(ArgumentError, "meta value: 1 is not a registered key and type") }
    end

    context "with an array of mixed types" do
      let(:meta) { {allowed_values: ["day", 1]} }

      it { expect { checked }.to raise_error(ArgumentError, 'meta allowed_values: ["day", 1] is not a registered key and type') }
    end

    context "with value" do
      let(:meta) { {value: "abc"} }

      it { expect { checked }.to raise_error(ArgumentError, "meta value echoes the request, which only a 400 may do") }
    end

    context "with invalid_values" do
      let(:meta) { {invalid_values: %w[rates]} }

      it { expect { checked }.to raise_error(ArgumentError, "meta invalid_values echoes the request, which only a 400 may do") }
    end

    context "with echo" do
      subject(:checked) { described_class.check(meta, echo: true) }

      let(:meta) { {value: "abc", invalid_values: %w[rates], min: 1} }

      it { expect(checked).to eq(value: "abc", invalid_values: %w[rates], min: 1) }
    end

    context "when the environment is not local" do
      let(:meta) { {:min => 1, :max => 1.5, :count => 2, 1 => 2, :value => "abc"} }

      before do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Sentry).to receive(:capture_exception)
      end

      it "drops the bad keys and reports each one" do
        expect(checked).to eq(min: 1)
        expect(Sentry).to have_received(:capture_exception).exactly(4).times
        expect(Sentry).to have_received(:capture_exception).with(an_object_having_attributes(message: "meta max: 1.5 is not a registered key and type"))
        expect(Sentry).to have_received(:capture_exception).with(an_object_having_attributes(message: "meta count: 2 is not a registered key and type"))
        expect(Sentry).to have_received(:capture_exception).with(an_object_having_attributes(message: "meta 1: 2 is not a registered key and type"))
        expect(Sentry).to have_received(:capture_exception).with(an_object_having_attributes(message: "meta value echoes the request, which only a 400 may do"))
      end

      context "with a String instead of a Hash" do
        let(:meta) { "min" }

        it "drops the meta and reports it" do
          expect(checked).to eq({})
          expect(Sentry).to have_received(:capture_exception).once
          expect(Sentry).to have_received(:capture_exception).with(an_object_having_attributes(message: "meta is not a Hash: String"))
        end
      end
    end
  end
end
