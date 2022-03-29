# frozen_string_literal: true

require "dry/effects"

module ROM
  module Plugins
    module Relation
      module SQL
        # Generates methods for restricting relations by their indexed attributes
        #
        # @example
        #   rom = ROM.container(:sql, 'sqlite::memory') do |config|
        #     config.create_table(:users) do
        #       primary_key :id
        #       column :email, String, null: false, unique: true
        #     end
        #
        #     config.plugin(:sql, relations: :auto_restrictions)
        #
        #     config.relation(:users) do
        #       schema(infer: true)
        #     end
        #   end
        #
        #   # now `by_email` is available automatically
        #   rom.relations[:users].by_email('jane@doe.org')
        #
        # @api public
        module AutoRestrictions
          extend Dry::Effects.Reader(:registry)

          # @api private
          def self.apply(target, **)
            methods, mod = AutoRestrictions.restriction_methods(registry.schemas.canonical(target))

            target.class_eval do
              include(mod)
              methods.each { |meth| auto_curry(meth) }
            end
          end

          # @api private
          # rubocop:disable Metrics/AbcSize
          def self.restriction_methods(schema)
            mod = Module.new

            methods = schema.indexes.each_with_object([]) do |index, generated|
              next if index.partial?

              attributes = index.to_a
              meth_name = :"by_#{ attributes.map(&:name).join("_and_") }"

              next if generated.include?(meth_name)

              mod.module_eval do
                if attributes.size == 1
                  attribute = attributes[0]

                  define_method(meth_name) do |value|
                    where(attribute.is(value))
                  end
                else
                  indexed_attributes = attributes.map.with_index.to_a

                  define_method(meth_name) do |*values|
                    where(indexed_attributes.map { |attr, idx| attr.is(values[idx]) }.reduce(:&))
                  end
                end
              end

              generated << meth_name
            end

            [methods, mod]
          end
          # rubocop:enable Metrics/AbcSize
        end
      end
    end
  end
end

ROM.plugins do
  adapter(:sql) do
    register :auto_restrictions, ROM::Plugins::Relation::SQL::AutoRestrictions, type: :relation
  end
end
