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

  describe "#serialize" do
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

        def serialize = {code: "parent"}
      end
    end

    it "adds the included expansions after its own payload, in their declared order, a missing record as nil" do
      expect(payload.to_a).to eq([[:code, "parent"], [:first, {code: "first", options: {}}], [:second, nil]])
    end

    it "renders the embedded record without includes, so that it stays flat" do
      expect(payload[:first][:options]).to eq({})
    end

    it "renders a Struct as one record, though it is Enumerable" do
      expect(first_record).to be_a(Enumerable)
      expect(payload[:first]).to eq(code: "first", options: {})
    end

    context "with the usec_timestamps include" do
      let(:options) { {includes: %i[first usec_timestamps]} }

      it "passes it on to the embedded record, and no expansion" do
        expect(payload).to eq(code: "parent", first: {code: "first", options: {includes: %i[usec_timestamps]}})
      end
    end

    context "with a private method named after an expansion" do
      let(:options) { {includes: %i[first third], label: "from the options"} }

      let(:serializer_class) do
        embedded_serializer = self.embedded_serializer

        Class.new(described_class) do
          expandable :first, serializer: embedded_serializer
          expandable :third, serializer: embedded_serializer

          def serialize = {code: "parent"}

          private

          def first = Struct.new(:code).new("#{model.first.code} #{options[:label]}")

          # model.third is a record: the method decides what renders.
          def third = nil
        end
      end

      it "renders what the method returns instead of the model's record, nil as null" do
        expect(payload).to eq(
          code: "parent",
          first: {code: "first from the options", options: {}},
          third: nil
        )
      end
    end

    # `test` and `format` are private methods of Kernel, and `options` a method of ModelSerializer.
    context "with an expansion named after an inherited method" do
      let(:model) { Struct.new(:test, :format, :options).new(first_record, first_record, first_record) }
      let(:options) { {includes: %i[test format options]} }

      let(:serializer_class) do
        embedded_serializer = self.embedded_serializer

        Class.new(described_class) do
          expandable :test, serializer: embedded_serializer
          expandable :format, serializer: embedded_serializer
          expandable :options, serializer: embedded_serializer

          def serialize = {code: "parent"}
        end
      end

      it "renders the model's record" do
        expect(payload).to eq(
          code: "parent",
          test: {code: "first", options: {}},
          format: {code: "first", options: {}},
          options: {code: "first", options: {}}
        )
      end
    end

    context "with list sources" do
      let(:model) { Struct.new(:first, :second, :third).new([first_record, second_record], taxes_relation, Tax.none) }
      let(:second_record) { Struct.new(:code).new("second") }
      let(:organization) { create(:organization) }
      let(:taxes_relation) { Tax.where(id: [create(:tax, organization:, code: "b"), create(:tax, organization:, code: "a")]).order(:code) }
      let(:options) { {includes: %i[first second third]} }

      it "renders an Array and an ActiveRecord relation as lists of records, each without includes" do
        expect(payload).to eq(
          code: "parent",
          first: [{code: "first", options: {}}, {code: "second", options: {}}],
          second: [{code: "a", options: {}}, {code: "b", options: {}}],
          third: []
        )
      end

      context "with the usec_timestamps include" do
        let(:options) { {includes: %i[first second third usec_timestamps]} }
        let(:nested) { {includes: %i[usec_timestamps]} }

        it "passes it on to every record of the lists" do
          expect(payload).to eq(
            code: "parent",
            first: [{code: "first", options: nested}, {code: "second", options: nested}],
            second: [{code: "a", options: nested}, {code: "b", options: nested}],
            third: []
          )
        end
      end
    end

    context "without includes" do
      let(:options) { {} }

      it "renders its own payload only" do
        expect(payload).to eq(code: "parent")
      end
    end

    context "with a serializer that declares no expansion" do
      let(:serializer_class) { Class.new(described_class) { def serialize = {code: "parent"} } }

      it "renders its own payload only" do
        expect(payload).to eq(code: "parent")
      end
    end
  end

  # Through a serializer of its own, as the V2 serializers call them.
  describe "#format_time" do
    subject(:formatted) { serializer_class.new(Struct.new(:at).new(value), options).serialize[:at] }

    let(:serializer_class) { Class.new(described_class) { def serialize = {at: format_time(model.at)} } }
    let(:value) { Time.zone.parse("2026-03-22T12:00:00.123456Z") }
    let(:options) { {includes: %i[usec_timestamps]} }

    it "renders the microseconds" do
      expect(formatted).to eq("2026-03-22T12:00:00.123456Z")
    end

    context "with a time on a whole second" do
      let(:value) { Time.zone.parse("2026-03-22T12:00:00Z") }

      it "renders six zero digits" do
        expect(formatted).to eq("2026-03-22T12:00:00.000000Z")
      end
    end

    context "without the usec_timestamps include" do
      let(:options) { {includes: %i[counts]} }

      it "renders whole seconds" do
        expect(formatted).to eq("2026-03-22T12:00:00Z")
      end
    end

    context "without includes" do
      let(:options) { {} }

      it "renders whole seconds" do
        expect(formatted).to eq("2026-03-22T12:00:00Z")
      end
    end

    context "with nil" do
      let(:value) { nil }

      it "renders nil" do
        expect(formatted).to be_nil
      end
    end
  end

  describe "#format_date" do
    subject(:formatted) { serializer_class.new(Struct.new(:on).new(value), options).serialize[:on] }

    let(:serializer_class) { Class.new(described_class) { def serialize = {on: format_date(model.on)} } }
    let(:value) { Date.new(2026, 3, 22) }
    let(:options) { {includes: %i[usec_timestamps]} }

    it "renders the day only" do
      expect(formatted).to eq("2026-03-22")
    end

    context "without the usec_timestamps include" do
      let(:options) { {} }

      it "renders the same day" do
        expect(formatted).to eq("2026-03-22")
      end
    end

    context "with nil" do
      let(:value) { nil }

      it "renders nil" do
        expect(formatted).to be_nil
      end
    end
  end
end
