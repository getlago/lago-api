# frozen_string_literal: true

RSpec.describe ModelSerializer do
  let(:serializer) { described_class.new(model, options) }

  let(:model) { double }

  describe "#include?" do
    # rubocop:disable RSpec/PredicateMatcher
    context "when includes is blank" do
      let(:options) { {includes: []} }

      it "returns false" do
        expect(serializer.include?(:id)).to be_falsey
      end
    end

    context "when includes is not blank" do
      let(:model) { double }

      context "with flat includes" do
        let(:options) { {includes: [:id, :name]} }

        it "returns true when the value is included" do
          expect(serializer.include?(:id)).to be_truthy
        end

        it "returns false when the value is not included" do
          expect(serializer.include?(:email)).to be_falsey
        end
      end

      context "with nested includes" do
        let(:options) { {includes: [:id, {name: [:first, :last]}]} }

        it "returns true for included attributes" do
          expect(serializer.include?(:id)).to be_truthy
        end

        it "returns true for included associations" do
          expect(serializer.include?(:name)).to be_truthy
        end

        it "returns false for nested attributes" do
          expect(serializer.include?(:first)).to be_falsey
        end

        it "returns false for unknown attributes" do
          expect(serializer.include?(:foo)).to be_falsey
        end
      end
    end
    # rubocop:enable RSpec/PredicateMatcher
  end

  describe "#included_relations" do
    context "when includes is blank" do
      let(:options) { {includes: []} }

      it "returns an empty array" do
        expect(serializer.included_relations(:id)).to eq([])
      end

      context "with a default value" do
        let(:options) { {includes: []} }

        it "returns an empty array" do
          expect(serializer.included_relations(:id, default: [:id])).to eq([:id])
        end
      end
    end

    context "when includes is not blank" do
      context "with flat includes" do
        let(:options) { {includes: [:id, :name]} }

        it "returns an empty array for symbols" do
          expect(serializer.included_relations(:id)).to eq([])
        end

        context "with a default value" do
          let(:options) { {includes: [:id, :name]} }

          it "returns an empty array" do
            expect(serializer.included_relations(:name, default: [:first, :last])).to eq([:first, :last])
          end
        end
      end

      context "with nested includes" do
        let(:options) { {includes: [:id, {name: [:first, :last]}]} }

        it "returns an array of included attributes" do
          expect(serializer.included_relations(:name)).to eq([:first, :last])
        end
      end

      context "when include is not found" do
        let(:options) { {includes: [:id]} }

        it "returns an empty array" do
          expect(serializer.included_relations(:name)).to eq([])
        end
      end
    end
  end

  describe ".expandable_relations" do
    it "is empty and frozen by default" do
      expect(described_class.expandable_relations).to eq({}).and be_frozen
    end
  end

  describe "#expanded_payload" do
    subject(:payload) { serializer.serialize }

    let(:serializer) { serializer_class.new(model, options) }
    let(:options) { {includes: %i[second unlisted first]} }

    context "with an expandable list" do
      let(:serializer_class) do
        Class.new(described_class) do
          def self.expandable_relations = {first: :first, second: nil, third: nil}.freeze

          def serialize = expanded_payload

          private

          def expand_first = "first expansion"

          def expand_second = "second expansion"

          def expand_third = "third expansion"
        end
      end

      before { allow(serializer).to receive(:expand_third).and_call_original }

      it "renders the included names, in the order of the list" do
        expect(payload.to_a).to eq([[:first, "first expansion"], [:second, "second expansion"]])
      end

      it "calls no other expansion" do
        payload

        expect(serializer).not_to have_received(:expand_third)
      end
    end

    context "without an expandable list" do
      let(:serializer_class) { Class.new(described_class) { def serialize = expanded_payload } }

      it "renders nothing" do
        expect(payload).to eq({})
      end
    end
  end
end
