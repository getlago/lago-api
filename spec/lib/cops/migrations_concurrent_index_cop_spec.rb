# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::MigrationsConcurrentIndexCop, :config do
  describe "add_index" do
    it "registers an offense when the algorithm is missing" do
      expect_offense(<<~RUBY)
        add_index :fees, :contract_id, if_not_exists: true
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use algorithm: :concurrently when adding an index in a migration.
      RUBY
    end

    it "registers an offense when the algorithm is not concurrent" do
      expect_offense(<<~RUBY)
        add_index(:fees, :contract_id, algorithm: :default)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use algorithm: :concurrently when adding an index in a migration.
      RUBY
    end

    it "allows a concurrent index with other options" do
      expect_no_offenses(<<~RUBY)
        class AddFeesIndex < ActiveRecord::Migration[8.0]
          disable_ddl_transaction!

          def change
            add_index :fees, :contract_id, unique: true, algorithm: :concurrently, if_not_exists: true
          end
        end
      RUBY
    end

    it "registers an offense when the migration does not disable DDL transactions" do
      expect_offense(<<~RUBY)
        class AddFeesIndex < ActiveRecord::Migration[8.0]
          def change
            add_index :fees, :id, algorithm: :concurrently
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Call disable_ddl_transaction! on the migration class when adding an index concurrently.
          end
        end
      RUBY
    end

    it "requires disable_ddl_transaction! at the class level" do
      expect_offense(<<~RUBY)
        class AddFeesIndex < ActiveRecord::Migration[8.0]
          def change
            disable_ddl_transaction!
            add_index :fees, :id, algorithm: :concurrently
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Call disable_ddl_transaction! on the migration class when adding an index concurrently.
          end
        end
      RUBY
    end

    it "ignores other methods and calls on a receiver" do
      expect_no_offenses(<<~RUBY)
        remove_index :fees, :contract_id
        helper.add_index :fees, :contract_id
      RUBY
    end
  end
end
