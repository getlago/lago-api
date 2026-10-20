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

  describe ".expandable" do
    let(:serializer_class) { Class.new(described_class) { expandable :first, serializer: ModelSerializer } }

    it "declares nothing by default" do
      expect(described_class.expandable_names).to eq([])
    end

    it "lists the declared names, in their order" do
      serializer_class.expandable :second, serializer: described_class

      expect(serializer_class.expandable_names).to eq(%i[first second])
    end

    it "leaves the other serializers' list unchanged" do
      serializer_class

      expect(described_class.expandable_names).to eq([])
    end
  end

  describe "#expanded_payload" do
    subject(:payload) { serializer_class.new(model, options).serialize }

    let(:model) { Struct.new(:first, :second, :third).new(first_record, nil, first_record) }
    let(:first_record) { Struct.new(:code).new("first") }
    let(:options) { {includes: %i[second unlisted first]} }

    # Renders what it was given, so that an embedded record shows the options it received.
    let(:embedded_serializer) { Class.new(described_class) { def serialize = {code: model.code, options:} } }

    let(:serializer_class) do
      embedded_serializer = self.embedded_serializer

      Class.new(described_class) do
        expandable :first, serializer: embedded_serializer
        expandable :second, serializer: embedded_serializer
        expandable :third, serializer: embedded_serializer

        def serialize = expanded_payload
      end
    end

    it "renders the included names in their declared order, a missing record as nil" do
      expect(payload.to_a).to eq([[:first, {code: "first", options: {}}], [:second, nil]])
    end

    it "renders the embedded record without includes, so that it stays flat" do
      expect(payload[:first][:options]).to eq({})
    end

    context "without includes" do
      let(:options) { {} }

      it "renders nothing" do
        expect(payload).to eq({})
      end
    end
  end
end
