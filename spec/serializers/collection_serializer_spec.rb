# frozen_string_literal: true

RSpec.describe CollectionSerializer do
  subject(:payload) { described_class.new(records, serializer, includes: [:usec_timestamps]).serialize }

  let(:records) { [Struct.new(:id).new("first"), Struct.new(:id).new("second")] }
  let(:serializer) { ModelSerializer }

  it "keeps serialization unchanged for serializers without collection options" do
    expect(payload).to eq(data: [{id: "first"}, {id: "second"}])
  end

  context "when the serializer prepares collection options" do
    let(:serializer) do
      Class.new(ModelSerializer) do
        def self.collection_options(records, options)
          options.merge(ids: records.map(&:id))
        end

        def serialize
          {id: model.id, ids: options[:ids], includes: options[:includes]}
        end
      end
    end

    it "shares the prepared options with every record" do
      expect(payload).to eq(data: [
        {id: "first", ids: %w[first second], includes: [:usec_timestamps]},
        {id: "second", ids: %w[first second], includes: [:usec_timestamps]}
      ])
    end
  end
end
