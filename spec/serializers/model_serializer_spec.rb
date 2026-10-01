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

  describe "#nested_includes" do
    subject(:nested_includes) { serializer.send(:nested_includes, forward: %i[counts]) }

    let(:options) { {includes: %i[product counts deleted_at]} }

    it "keeps deleted_at and the forwarded options, never an expansion" do
      expect(nested_includes).to eq(%i[deleted_at counts])
    end

    context "without forwarded options" do
      subject(:nested_includes) { serializer.send(:nested_includes) }

      it "keeps deleted_at only" do
        expect(nested_includes).to eq(%i[deleted_at])
      end
    end

    context "without internal options" do
      let(:options) { {includes: %i[product]} }

      it "returns nothing" do
        expect(nested_includes).to eq([])
      end
    end

    context "without includes" do
      let(:options) { {} }

      it "returns nothing" do
        expect(nested_includes).to eq([])
      end
    end
  end

  describe "#deleted_at_payload" do
    subject(:payload) { serializer.send(:deleted_at_payload) }

    let(:model) { build_stubbed(:product, deleted_at:) }
    let(:deleted_at) { Time.zone.parse("2026-03-22T12:00:00Z") }
    let(:options) { {includes: %i[deleted_at]} }

    it "renders deleted_at in ISO 8601" do
      expect(payload).to eq(deleted_at: "2026-03-22T12:00:00Z")
    end

    context "when the record is kept" do
      let(:deleted_at) { nil }

      it "renders a null deleted_at" do
        expect(payload).to eq(deleted_at: nil)
      end
    end

    context "without the deleted_at option" do
      let(:options) { {includes: %i[counts]} }

      it "renders nothing" do
        expect(payload).to eq({})
      end
    end
  end
end
