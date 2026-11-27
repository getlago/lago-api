# frozen_string_literal: true

require "cop_helper"

RSpec.describe Cops::ModelSettingsAfterConstantsCop, :config do
  it "accepts settings right after the includes and the constants" do
    expect_no_offenses(<<~RUBY)
      class Invoice < ApplicationRecord
        include Discard::Model
        STATUSES = %w[draft].freeze
        private_constant :STATUSES

        self.discard_column = :deleted_at
        self.ignored_columns += %w[legacy]

        belongs_to :customer

        def finalize
          self.status = :finalized
        end
      end
    RUBY
  end

  it "accepts a class without includes or constants" do
    expect_no_offenses(<<~RUBY)
      class Invoice < ApplicationRecord
        self.table_name = "invoices"
        belongs_to :customer
      end
    RUBY
  end

  it "registers an offense for a setting before a constant" do
    expect_offense(<<~RUBY)
      class Invoice < ApplicationRecord
        self.table_name = "invoices"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Put class settings such as `self.table_name =` right after the includes and the constants.
        STATUSES = %w[draft].freeze
      end
    RUBY
  end

  it "registers an offense for a setting before an include" do
    expect_offense(<<~RUBY)
      class Invoice < ApplicationRecord
        self.discard_column = :deleted_at
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Put class settings such as `self.table_name =` right after the includes and the constants.
        include Discard::Model
      end
    RUBY
  end

  it "registers an offense for a setting after a macro" do
    expect_offense(<<~RUBY)
      class Invoice < ApplicationRecord
        belongs_to :customer
        self.ignored_columns += %w[legacy]
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Put class settings such as `self.table_name =` right after the includes and the constants.
      end
    RUBY
  end

  it "registers an offense for a setting after a method" do
    expect_offense(<<~RUBY)
      class Invoice < ApplicationRecord
        def total
        end

        self.primary_key = :id
        ^^^^^^^^^^^^^^^^^^^^^^ Put class settings such as `self.table_name =` right after the includes and the constants.
      end
    RUBY
  end
end
