require 'activerecord'

# This plugin allows you to painlessly move away from column based lookups to normalized lookup tables.
#
# Simply add "acts_as_lookup" to your lookup table models.
#
# The assumed schema inclueds a "name" column which is used as the "key column".
# The "key column" is the column that holds the values that are used to key off of.
# The "key column" allows you to code against expected values in the database
# rather than hard coding with primary key values.
#
# This is generally safe considering that lookup data is relatively static.
#
# Consider the following schema:
# ----------------------------------------------------
# addresses
#  * id
#  * street
#  * state_id
#  * zip
#
# states
#  * id
#  * name => "UT, GA, IL, etc..."
#  * description
# ----------------------------------------------------
#
# Here are some examples of what this plugin provides when working with a lookup table directly:
#
# Obtain id from a lookup table like so:
#  utah_id = State.ut(:id)
#
# Obtain the description like so:
#  utah_desc = State.ut(:description)
#
# The real power comes with models that contain "belongs_to" relationships to parents that act_as_lookup.
# These models implicitly mixin some additional behavior that make working with lookup tables
# as simple as using columns directly on the table itself.
#
# For example:
#
# You can select with the following syntax:
#  Address.find_by_state("UT")
#
# You can also assign like so:
#  addr = Address.new
#  addr.state = "UT"
#
# If a state with "UT" doesn't exist in the states table, one will be implicitly created.
# The requirement being that the model validates correctly.  In this case only a name is assigned.
module Hopsoft
  module ActsAsLookup

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods

      # Adds lookup table behavior to a model.
      def acts_as_lookup(options={})
        @key_column = options[:key_column] || :name
        include Hopsoft::ActsAsLookup::IsLookup::InstanceMethods
        extend Hopsoft::ActsAsLookup::IsLookup::StaticMethods
        init
      end

      # Used to implicitly mixin additional behavior for models that contain "belongs_to"
      # relationships to lookup tables.
      def belongs_to(association_id, options={})
        result = super

        begin
          parent_model_name = options[:class_name] || association_id.to_s.camelize
          parent_model = Object.const_get(parent_model_name)
          parent_acts_as_lookup = defined?(parent_model.key_column)

          # only add the behavior for belongs_to relationships where the parent implements "acts_as_lookup".
          if parent_acts_as_lookup
            @lookup_models ||= []
            @lookup_models << parent_model

            unless @lookup_behavior_added
              include Hopsoft::ActsAsLookup::UsesLookups::InstanceMethods
              extend Hopsoft::ActsAsLookup::UsesLookups::StaticMethods
              @lookup_behavior_added = true
            end
          end
        rescue
          puts("LookupTables plugin error!  Unable to override belongs_to for '#{parent_model_name}'!\n#{$!}")
        end

        result
      end
    end

    # This module is implicitly mixed into any models that specify "belongs_to" using an "acts_as_lookup" model.
    # Provides some helpful tools for selecting and assigning values for lookup tables.
    # See the plugin description for more details.
    module UsesLookups

      # Add class methods here
      module StaticMethods
        attr_reader :lookup_models

        def method_missing(name, *args)
          if name =~ /^find_by_/i && args && args.length == 1
            @lookup_models.each do |model|
              attribute_name = model.table_name.singularize

              if name =~ /#{attribute_name}$/i
                # if we get here, assume a lookup is being performed
                return lookup_parent(model, args[0])
              end
            end
          end

          super
        end

        private

        # Attempts to find a parent record based on the passed value.
        # The parent model must implement "acts_as_lookup" for this method to work as expected.
        #
        # Exmaple:
        #  Message.find_by_message_status :pending
        def lookup_parent(parent_model, value)
          value = value.to_s.downcase.gsub(/ /, "_")
          return send("find_by_#{parent_model.table_name.singularize}_id", parent_model.send(value, :id))
        end

      end

      # Add instance methods here
      module InstanceMethods

      end

    end

    module IsLookup

      # Add class methods here
      module StaticMethods
        attr_reader :key_column

        def method_missing(name, *args)

          if args && args.length == 1
            column_name = args[0].to_s.downcase

            if column_name =~ /^object$/
              return get_record(name)
            else
              if @lookup_columns.include?(column_name)
                # once here we are assuming they are performing a lookup
                return get_column_value(name, column_name)
              end
            end
          end

          return super
        end

        # Gets a column's value from an "acts_as_lookup" model.
        #
        # ===Params
        # * *value* - The "key column" value to find.
        # * *column_name* - The column's name to return a value for.
        def get_column_value(value, column_name)
          record = get_record(value)
          return record.attributes[column_name] if record
          return nil
        end

        # Gets an ActiveRecord object from an "acts_as_lookup" model.
        #
        # ===Params
        # * *value* - The "key column" value to find.
        def get_record(value)
          value = value.to_s.downcase.gsub(/_/, " ")
          finder_method = "find_by_#{@key_column}"
          item = send(finder_method, value)
          item
        end

        # Initializes the plugin.
        def init
          @lookup_columns = new.attributes.keys.map {|attr_name| attr_name.downcase.gsub(/ /, "_") }
          @lookup_columns << "id"
        end

      end

      # Add instance methods here
      module InstanceMethods

        def to_s
          return name
        end

        def ==(value)
          return name == value if value.is_a?(String)
          return name == value.to_s if value.is_a?(Symbol)
          return id == value.id if self.class == value.class
          return self.object_id == value.object_id
        end

        def =~(value)
          return name =~ value if value.is_a?(Regexp)
          return name =~ /#{value}/i if value.is_a?(String)
          return name =~ /#{value.to_s}/i if value.is_a?(Symbol)
          return false
        end

      end

    end

  end
end

module ActiveRecord
  class Migration

    # Migration helper for creating a standardized lookup table.
    def self.create_lookup_table(name)
      create_table name do |t|
        # lookup columns
        t.column :name, :string, :limit => 50, :null => false
        t.column :description, :text
        t.column :enabled, :boolean, :default => true, :null => false
        t.column :sort_order, :integer, :default => 0, :null => false
      end rescue
      add_index(name, :name, :unique => true)
    end

  end

  module Associations
    class BelongsToAssociation
      alias :orig_replace :replace

      # Overriding "replace" to allow implicit lookup table insertions.
      # The assumption being that the only required field is the specified "key column" or
      # in other words the column whose value we use to key off of.
      def replace(record)
        if record.is_a?(Symbol) || record.is_a?(String)
          value = record.to_s
          attribute_name = proxy_reflection.table_name.singularize
          lookup_models = proxy_owner.class.lookup_models

          lookup_models.each do |model|
            if attribute_name =~ /^#{model.table_name.singularize}$/i
              record = model.get_record(value)

              if record.nil?
                new_record = model.new(model.key_column.to_sym => value)
                record = new_record if new_record.save
              end

              break
            end
          end

        end

        return orig_replace(record)
      end

    end
  end
end

module ApplicationHelper
  def select_from_lookup(table, options = {})
    if table.is_a?(Symbol) || table.is_a?(String)
      model = Object.const_get(table.to_s.classify)
      field ||= options[:field] || "name"
      collection = model.send(:find, :all)
      default ||= options[:value] || nil
      choices = options_from_collection_for_select(collection, "name", field, default)
      select_tag table, choices, options
    end
  end
end
