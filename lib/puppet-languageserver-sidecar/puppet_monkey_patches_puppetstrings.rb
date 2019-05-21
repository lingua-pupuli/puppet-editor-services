# frozen_string_literal: true

# Monkey Patch 3.x functions so where know where they were loaded from
require 'puppet/parser/functions'
module Puppet
  module Parser
    module Functions
      class << self
        alias_method :original_newfunction, :newfunction
        def newfunction(name, options = {}, &block)
          # See if we've hooked elsewhere. This can happen while in debuggers (pry). If we're not in the previous caller
          # stack then just use the last caller
          monkey_index = Kernel.caller_locations.find_index { |loc| loc.path.match(/puppet_monkey_patches\.rb/) }
          monkey_index = -1 if monkey_index.nil?
          caller = Kernel.caller_locations[monkey_index + 1]
          # Call the original new function method
          result = original_newfunction(name, options, &block)
          # Append the caller information
          result[:source_location] = {
            :source => caller.absolute_path,
            :line   => caller.lineno - 1 # Convert to a zero based line number system
          }
          monkey_append_function_info(name, result)

          result
        end

        def monkey_clear_function_info
          @monkey_function_list = {}
        end

        def monkey_append_function_info(name, value)
          @monkey_function_list = {} if @monkey_function_list.nil?
          @monkey_function_list[name] = {
            :arity           => value[:arity],
            :name            => value[:name],
            :type            => value[:type],
            :doc             => value[:doc],
            :source_location => value[:source_location]
          }
        end

        def monkey_function_list
          @monkey_function_list = {} if @monkey_function_list.nil?
          @monkey_function_list.clone
        end
      end
    end
  end
end

# Add an additional method on Puppet Types to store their source location
require 'puppet/type'
module Puppet
  class Type
    class << self
      attr_accessor :_source_location
    end
  end
end

# Monkey Patch type loading so we can inject the source location information
require 'puppet/metatype/manager'
module Puppet
  module MetaType
    module Manager
      alias_method :original_newtype, :newtype
      def newtype(name, options = {}, &block)
        result = original_newtype(name, options, &block)

        if block_given? && !block.source_location.nil?
          result._source_location = {
            :source => block.source_location[0],
            :line   => block.source_location[1] - 1 # Convert to a zero based line number system
          }
        end
        result
      end
    end
  end
end

if Gem::Version.new(Puppet.version) >= Gem::Version.new('6.0.0')
  # Due to PUP-9509, need to monkey patch the cache loader
  # This need to be guarded on Puppet 6.0.0+
  require 'puppet/pops/loader/module_loaders'
  module Puppet
    module Pops
      module Loader
        module ModuleLoaders
          def self.cached_loader_from(parent_loader, loaders)
            LibRootedFileBased.new(parent_loader,
                                   loaders,
                                   NAMESPACE_WILDCARD,
                                   Puppet[:libdir],
                                   'cached_puppet_lib',
                                   %i[func_4x func_3x datatype])
          end
        end
      end
    end
  end
end

module Puppet
  module Pops
    module Loader
      class Loader
        def discover_paths(type, name_authority = Pcore::RUNTIME_NAME_AUTHORITY)
          if parent.nil?
            []
          else
            parent.discover_paths(type, name_authority)
          end
        end
      end
    end
  end
end

# While this is not a monkey patch, but a new class, this class is used purely to
# enumerate the paths of puppet "things" that aren't already covered as part of the
# usual loaders. It is implemented as a null loader as it can't actually _load_
# anything.
module Puppet
  module Pops
    module Loader
      class PathDiscoveryNullLoader < Puppet::Pops::Loader::NullLoader
        def discover_paths(type, name_authority = Pcore::RUNTIME_NAME_AUTHORITY)
          result = []

          if type == :type
            autoloader = Puppet::Util::Autoload.new(self, 'puppet/type')
            current_env = current_environment

            # This is an expensive call
            if autoloader.method(:files_to_load).arity.zero?
              params = []
            else
              params = [current_env]
            end
            autoloader.files_to_load(*params).each do |file|
              name = file.gsub(autoloader.path + '/', '')
              expanded_name = autoloader.expand(name)
              absolute_name = Puppet::Util::Autoload.get_file(expanded_name, current_env)
              result << absolute_name unless absolute_name.nil?
            end
          end

          if type == :sidecar_manifest
            current_environment.modules.each do |mod|
              result.concat(mod.all_manifests)
            end
          end

          result.concat(super)
          result.uniq
        end

        private

        def current_environment
          begin
            env = Puppet.lookup(:environments).get!(Puppet.settings[:environment])
            return env unless env.nil?
          rescue Puppet::Environments::EnvironmentNotFound
            PuppetLanguageServerSidecar.log_message(:warning, "[Puppet::Pops::Loader::PathDiscoveryNullLoader::current_environment] Unable to load environment #{Puppet.settings[:environment]}")
          rescue StandardError => e
            PuppetLanguageServerSidecar.log_message(:warning, "[Puppet::Pops::Loader::PathDiscoveryNullLoader::current_environment] Error loading environment #{Puppet.settings[:environment]}: #{e}")
          end
          Puppet.lookup(:current_environment)
        end
      end
    end
  end
end

module Puppet
  module Pops
    module Loader
      class DependencyLoader
        def discover_paths(type, name_authority = Pcore::RUNTIME_NAME_AUTHORITY)
          result = []

          @dependency_loaders.each { |loader| result.concat(loader.discover_paths(type, name_authority)) }
          result.concat(super)
          result.uniq
        end
      end
    end
  end
end

module Puppet
  module Pops
    module Loader
      module ModuleLoaders
        class AbstractPathBasedModuleLoader
          def discover_paths(type, name_authority = Pcore::RUNTIME_NAME_AUTHORITY)
            result = []
            if name_authority == Pcore::RUNTIME_NAME_AUTHORITY
              smart_paths.effective_paths(type).each do |sp|
                relative_paths(sp).each do |rp|
                  result << File.join(sp.generic_path, rp)
                end
              end
            end
            result.concat(super)
            result.uniq
          end
        end
      end
    end
  end
end

# MUST BE LAST!!!!!!
# Suppress any warning messages to STDOUT.  It can pollute stdout when running in STDIO mode
Puppet::Util::Log.newdesttype :null_logger do
  def handle(msg)
    PuppetLanguageServerSidecar.log_message(:debug, "[PUPPET LOG] [#{msg.level}] #{msg.message}")
  end
end
