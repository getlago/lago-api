# frozen_string_literal: true

require "rails_helper"

RSpec.describe Metadata::ItemMetadata do
  subject(:item_metadata) { described_class.new(organization:, owner:, value:) }

  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice, organization:) }
  let(:customer) { invoice.customer }
  let(:owner) { create(:credit_note, invoice:, customer:, organization:) }
  let(:value) { {"key1" => "value1"} }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:owner) }

  describe "validations" do
    describe "of value not being nil" do
      context "when value is nil" do
        let(:value) { nil }

        it "adds an error" do
          expect(item_metadata).not_to be_valid
          expect(item_metadata.errors[:value]).to be_present
        end
      end

      context "when value is an empty hash" do
        let(:value) { {} }

        it "is valid" do
          expect(item_metadata).to be_valid
        end
      end
    end

    describe "of owner uniqueness" do
      context "when owner is nil" do
        let(:owner) { nil }

        it "adds an error" do
          expect(item_metadata).not_to be_valid
          expect(item_metadata.errors[:owner]).to be_present
        end
      end

      context "when owner is already taken" do
        before { described_class.create!(organization:, owner:, value:) }

        it "is valid at app level but raises database error on save" do
          expect(item_metadata).to be_valid
          expect { item_metadata.save! }.to raise_error(ActiveRecord::RecordNotUnique)
        end
      end
    end

    describe "of value correctness" do
      context "when value is valid" do
        let(:value) { {"key1" => "value1", "key2" => "value2"} }

        it { expect(item_metadata).to be_valid }
      end

      context "when value is not a Hash" do
        let(:value) { "not a hash" }

        it "adds an error" do
          expect(item_metadata).not_to be_valid
          expect(item_metadata.errors[:value]).to include("must be a Hash")
        end
      end

      context "when value has more than 50 keys" do
        let(:value) { 51.times.to_h { |i| ["key#{i}", "value#{i}"] } }

        it "adds an error" do
          expect(item_metadata).not_to be_valid
          expect(item_metadata.errors[:value]).to include("cannot have more than 50 keys")
        end
      end

      context "when key is empty" do
        let(:value) { {"" => "value"} }

        it "is valid" do
          expect(item_metadata).to be_valid
        end
      end

      context "when key length is more than 50" do
        let(:value) { {("a" * 51) => "value"} }

        it "adds an error" do
          key = "a" * 51
          expect(item_metadata).not_to be_valid
          expect(item_metadata.errors[:value]).to include("key '#{key}' must be a String up to 50 characters")
        end
      end

      context "when value is nil" do
        let(:value) { {"foo" => nil} }

        it "is valid" do
          expect(item_metadata).to be_valid
        end
      end

      context "when value is not a String" do
        let(:value) { {"foo" => 123} }

        it "is valid" do
          expect(item_metadata).to be_valid
        end
      end

      context "when value length is less than 1" do
        let(:value) { {"foo" => ""} }

        it "is valid" do
          expect(item_metadata).to be_valid
        end
      end

      context "when value length is more than 255" do
        let(:value) { {"foo" => "a" * 256} }

        it "adds an error" do
          expect(item_metadata).not_to be_valid
          expect(item_metadata.errors[:value].join).to include("value for key 'foo' must be up to 255 characters")
        end
      end

      context "when value has multiple value types inside" do
        context "when value has an array" do
          context "and array size is more than 50" do
            let(:value) { {"foo" => Array.new(51, "item")} }

            it "adds an error" do
              expect(item_metadata).not_to be_valid
              expect(item_metadata.errors[:value]).to include("value for key 'foo' cannot have more than 50 items")
            end
          end

          context "and array size is 50 or less" do
            let(:value) { {"foo" => Array.new(50, "item")} }

            it "is valid" do
              expect(item_metadata).to be_valid
            end
          end
        end

        context "when value has a hash" do
          context "when hash size is more than 50" do
            let(:value) { {"foo" => 51.times.to_h { |i| ["key#{i}", "value#{i}"] }} }

            it "adds an error" do
              expect(item_metadata).not_to be_valid
              expect(item_metadata.errors[:value]).to include("value for key 'foo' cannot have more than 50 keys")
            end
          end

          context "when hash size is 50 or less" do
            let(:value) { {"foo" => 50.times.to_h { |i| ["key#{i}", "value#{i}"] }} }

            it "is valid" do
              expect(item_metadata).to be_valid
            end
          end

          context "when one of the inner values exceeds 500 characters in JSON size" do
            let(:large_string) { "a" * 501 }
            let(:value) { {"foo" => {"inner_key" => large_string}} }

            it "adds an error" do
              expect(item_metadata).not_to be_valid
              expect(item_metadata.errors[:value]).to include("all values in hash for key 'foo' must have max json size of 500 characters")
            end
          end

          context "when inner values are within limits" do
            let(:value) do
              {
                "foo" => {
                  "inner_string" => "a" * 100,
                  "inner_array" => Array.new(10, "item"),
                  "inner_hash" => 10.times.to_h { |i| ["key#{i}", "value#{i}"] },
                  "inner_bool" => true,
                  "inner_integer" => 42,
                  "inner_nil" => nil
                },
                "hash_of_hashes" => {
                  "hash1" => 10.times.to_h { |i| ["key#{i}", "value#{i}"] },
                  "hash2" => 5.times.to_h { |i| ["key#{i}", {"child_key" => "child_value"}] }
                }
              }
            end

            it "is valid" do
              expect(item_metadata).to be_valid
            end
          end

          context "inner values are breaking size limit" do
            let(:value) do
              {
                "foo" => {
                  "inner_hash" => {
                    "key1" => 10.times.to_h { |i| ["key#{i}", "value#{i}_that_will_result_in_breaking_the_limits"] }
                  }
                }
              }
            end

            it "adds an error" do
              expect(item_metadata).not_to be_valid
              expect(item_metadata.errors[:value]).to include("all values in hash for key 'foo' must have max json size of 500 characters")
            end
          end
        end
      end
    end
  end

  describe "database constraints" do
    describe "NOT NULL constraints" do
      it "enforces organization_id presence" do
        item_metadata.organization_id = nil
        expect { item_metadata.save!(validate: false) }
          .to raise_error(ActiveRecord::NotNullViolation)
      end

      it "enforces owner_type presence" do
        item_metadata.owner_type = nil
        expect { item_metadata.save!(validate: false) }
          .to raise_error(ActiveRecord::NotNullViolation)
      end

      it "enforces owner_id presence" do
        item_metadata.owner_id = nil
        expect { item_metadata.save!(validate: false) }
          .to raise_error(ActiveRecord::NotNullViolation)
      end

      it "enforces value presence" do
        item_metadata.value = nil
        expect { item_metadata.save!(validate: false) }
          .to raise_error(ActiveRecord::NotNullViolation)
      end
    end

    describe "uniqueness constraint on owner" do
      it "prevents duplicate owner_type and owner_id combination" do
        described_class.create!(organization:, owner:, value:)

        new_item = described_class.new(organization:, owner:, value: {"key2" => "value2"})
        expect { new_item.save!(validate: false) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    describe "value must be JSON object constraint" do
      it "prevents non-object JSON values" do
        expect do
          described_class.connection.execute(<<~SQL.squish)
            INSERT INTO item_metadata (
              id, organization_id, owner_type, owner_id, value, created_at, updated_at
            ) VALUES (
              '#{SecureRandom.uuid}',
              '#{organization.id}',
              '#{owner.class.name}',
              '#{owner.id}',
              '[]',
              NOW(),
              NOW()
            )
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid)
      end
    end
  end
end
