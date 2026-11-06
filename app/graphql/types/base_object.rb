# frozen_string_literal: true

module Types
  class BaseObject < GraphQL::Schema::Object
    edge_type_class(Types::BaseEdge)
    connection_type_class(Types::BaseConnection)
    field_class Types::BaseField

    # Defines a field method that batches the named ActiveRecord associations
    # through `Sources::ActiveRecordAssociation`, preventing N+1 queries when
    # the same association is requested for several parent records in a single
    # GraphQL query.
    #
    # Usage:
    #   dataload_association :customer, :organization, :subscription
    def self.dataload_association(*names)
      names.each do |name|
        define_method(name) do
          dataloader.with(Sources::ActiveRecordAssociation, name).load(object)
        end
      end
    end

    # Defines field methods that batch an association through `Sources::ActiveRecordAssociation`
    # before calling the model method of the same name, for model methods that read it.
    #
    # Usage:
    #   dataload_association_for :organization, :file_url, :xml_url
    def self.dataload_association_for(association, *fields)
      fields.each do |field|
        define_method(field) do
          dataloader.with(Sources::ActiveRecordAssociation, association).load(object)
          object.public_send(field)
        end
      end
    end
  end
end
