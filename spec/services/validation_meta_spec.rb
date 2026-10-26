# frozen_string_literal: true

require "rails_helper"

RSpec.describe ValidationMeta do
  def reported(message)
    an_instance_of(ArgumentError).and(having_attributes(message:, backtrace: be_present))
  end

  describe ".check" do
    subject(:checked) { described_class.check(meta) }

    let(:meta) { {min: 1, max: 3, allowed_values: %w[day month], value: "abc", invalid_values: %w[rates]} }

    it "keeps the registered keys" do
      expect(checked).to eq(min: 1, max: 3, allowed_values: %w[day month], value: "abc", invalid_values: %w[rates])
      expect(checked).to be_frozen
    end

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

    context "without echo" do
      subject(:checked) { described_class.check(meta, echo: false) }

      let(:meta) { {min: 1, max: 3, allowed_values: %w[day month]} }

      it { expect(checked).to eq(min: 1, max: 3, allowed_values: %w[day month]) }

      context "with value" do
        let(:meta) { {value: "abc"} }

        it { expect { checked }.to raise_error(ArgumentError, "meta value echoes the request, which a validation error never does") }
      end

      context "with invalid_values" do
        let(:meta) { {invalid_values: %w[rates]} }

        it { expect { checked }.to raise_error(ArgumentError, "meta invalid_values echoes the request, which a validation error never does") }
      end
    end

    context "when the environment is not local" do
      let(:meta) { {:min => 1, :max => 1.5, :count => 2, 1 => 2} }

      before do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Sentry).to receive(:capture_exception)
      end

      it "drops the bad keys and reports each one" do
        expect(checked).to eq(min: 1)
        expect(Sentry).to have_received(:capture_exception).exactly(3).times
        expect(Sentry).to have_received(:capture_exception).with(reported("meta max: 1.5 is not a registered key and type"))
        expect(Sentry).to have_received(:capture_exception).with(reported("meta count: 2 is not a registered key and type"))
        expect(Sentry).to have_received(:capture_exception).with(reported("meta 1: 2 is not a registered key and type"))
      end

      context "with a String instead of a Hash" do
        let(:meta) { "min" }

        it "drops the meta and reports it" do
          expect(checked).to eq({})
          expect(Sentry).to have_received(:capture_exception).once
          expect(Sentry).to have_received(:capture_exception).with(reported("meta is not a Hash: String"))
        end
      end
    end
  end

  describe ".align" do
    subject(:aligned) { described_class.align(messages, meta) }

    let(:messages) do
      {
        position: %w[value_is_out_of_range value_is_invalid value_is_mandatory],
        billing_interval_unit: %w[value_is_invalid]
      }
    end
    let(:meta) { {position: [{min: 1, max: 3}]} }

    it "pads the meta of a field up to the number of its codes" do
      expect(aligned).to eq(position: [{min: 1, max: 3}, {}, {}])
      expect(aligned).to be_frozen
      expect(aligned[:position]).to be_frozen.and all(be_frozen)
    end

    context "without meta" do
      let(:meta) { {} }

      it { expect(aligned).to eq({}) }
    end

    context "with nil meta" do
      let(:meta) { nil }

      it { expect(aligned).to eq({}) }
    end

    context "with a String instead of a Hash" do
      let(:meta) { "min" }

      it { expect { aligned }.to raise_error(ArgumentError, "meta is not a Hash of fields: String") }
    end

    context "when every item of a field is empty" do
      let(:meta) { {position: [{}, {}], billing_interval_unit: [{allowed_values: %w[day week month year]}]} }

      it { expect(aligned).to eq(billing_interval_unit: [{allowed_values: %w[day week month year]}]) }
    end

    context "with nil items" do
      let(:meta) { {position: [nil, {max: 3}], billing_interval_unit: [nil]} }

      it { expect(aligned).to eq(position: [{}, {max: 3}, {}]) }
    end

    context "with meta for a field absent from messages" do
      let(:meta) { {name: [{max: 3}]} }

      it { expect { aligned }.to raise_error(ArgumentError, "meta of :name does not match its codes") }
    end

    context "with more items than codes" do
      let(:meta) { {billing_interval_unit: [{allowed_values: %w[day]}, {max: 3}]} }

      it { expect { aligned }.to raise_error(ArgumentError, "meta of :billing_interval_unit does not match its codes") }
    end

    context "with a Hash instead of a list" do
      let(:meta) { {position: {min: 1}} }

      it { expect { aligned }.to raise_error(ArgumentError, "meta of :position does not match its codes") }
    end

    context "with a String item" do
      let(:meta) { {position: ["min"]} }

      it { expect { aligned }.to raise_error(ArgumentError, "meta is not a Hash: String") }
    end

    context "with an Array item" do
      let(:meta) { {position: [[{min: 1}]]} }

      it { expect { aligned }.to raise_error(ArgumentError, "meta is not a Hash: Array") }
    end

    context "with String messages" do
      let(:messages) { "invalid_expression" }
      let(:meta) { {base: [{min: 1}]} }

      it { expect { aligned }.to raise_error(ArgumentError, "meta of :base does not match its codes") }
    end

    context "with nested messages" do
      let(:messages) { {rates: {0 => ["value_is_invalid"]}} }
      let(:meta) { {rates: [{min: 1}]} }

      it { expect { aligned }.to raise_error(ArgumentError, "meta of :rates does not match its codes") }
    end

    context "with an echo key" do
      let(:meta) { {position: [{value: "4"}]} }

      it { expect { aligned }.to raise_error(ArgumentError, "meta value echoes the request, which a validation error never does") }
    end

    context "when the environment is not local" do
      let(:meta) do
        {
          position: [{min: 1, max: 3}],
          name: [{max: 3}],
          billing_interval_unit: [{value: "hour"}]
        }
      end

      before do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Sentry).to receive(:capture_exception)
      end

      it "drops what does not match its codes and reports it" do
        expect(aligned).to eq(position: [{min: 1, max: 3}, {}, {}])
        expect(Sentry).to have_received(:capture_exception).twice
        expect(Sentry).to have_received(:capture_exception).with(reported("meta of :name does not match its codes"))
        expect(Sentry).to have_received(:capture_exception).with(reported("meta value echoes the request, which a validation error never does"))
      end

      context "with items that are not a Hash" do
        let(:meta) { {position: ["min", {max: 3}], billing_interval_unit: [[{min: 1}]]} }

        it "drops each of them and reports it" do
          expect(aligned).to eq(position: [{}, {max: 3}, {}])
          expect(Sentry).to have_received(:capture_exception).twice
          expect(Sentry).to have_received(:capture_exception).with(reported("meta is not a Hash: String"))
          expect(Sentry).to have_received(:capture_exception).with(reported("meta is not a Hash: Array"))
        end
      end

      context "with a String instead of a Hash" do
        let(:meta) { "min" }

        it "drops the meta and reports it" do
          expect(aligned).to eq({})
          expect(Sentry).to have_received(:capture_exception).once
          expect(Sentry).to have_received(:capture_exception).with(reported("meta is not a Hash of fields: String"))
        end
      end

      context "with String messages" do
        let(:messages) { "invalid_expression" }
        let(:meta) { {base: [{min: 1}]} }

        it "drops the meta and reports it" do
          expect(aligned).to eq({})
          expect(Sentry).to have_received(:capture_exception).once
          expect(Sentry).to have_received(:capture_exception).with(reported("meta of :base does not match its codes"))
        end
      end
    end
  end

  describe ".for_record" do
    subject(:record_meta) { described_class.for_record(record) }

    let(:record) { build(:rate_card_rate) }

    it { expect(record_meta).to eq({}) }

    context "with errors carrying meta" do
      before do
        record.errors.add(:billing_interval_count, :greater_than_or_equal_to, count: 1)
        record.errors.add(:code, :blank)
        record.errors.add(:billing_interval_count, :not_allowed_for_billing_timing, meta: {min: 1, max: 3})
        record.errors.add(:rate_model, :not_allowed_for_product, meta: {allowed_values: %w[standard package]})
      end

      it "returns the meta of each error under its attribute, at its position" do
        expect(record_meta).to eq(
          billing_interval_count: [{}, {min: 1, max: 3}],
          rate_model: [{allowed_values: %w[standard package]}]
        )
      end

      it "aligns with the messages of the record" do
        expect(record.errors.messages).to eq(
          billing_interval_count: %w[value_is_out_of_range not_allowed_for_billing_timing],
          code: %w[value_is_mandatory],
          rate_model: %w[not_allowed_for_product]
        )
        expect(record_meta.to_h { |attribute, items| [attribute, record.errors.messages[attribute].zip(items)] }).to eq(
          billing_interval_count: [["value_is_out_of_range", {}], ["not_allowed_for_billing_timing", {min: 1, max: 3}]],
          rate_model: [["not_allowed_for_product", {allowed_values: %w[standard package]}]]
        )
        expect(described_class.align(record.errors.messages, record_meta)).to eq(record_meta)
      end
    end
  end
end
