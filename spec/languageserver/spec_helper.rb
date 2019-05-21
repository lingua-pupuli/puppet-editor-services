# Emulate the setup from the root 'puppet-languageserver' file

root = File.join(File.dirname(__FILE__),'..','..')
# Add the language server into the load path
$LOAD_PATH.unshift(File.join(root,'lib'))
# Add the vendored gems into the load path
$LOAD_PATH.unshift(File.join(root,'vendor','puppet-lint','lib'))

require 'puppet_languageserver'
$fixtures_dir = File.join(File.dirname(__FILE__),'fixtures')

# Currently there is no way to re-initialize the puppet loader so for the moment
# all tests must run off the single puppet config settings instead of per example setting
server_options = PuppetLanguageServer::CommandLineParser.parse(['--slow-start'])
server_options[:puppet_settings] = ['--vardir',File.join($fixtures_dir,'cache'),
                                    '--confdir',File.join($fixtures_dir,'confdir')]
PuppetLanguageServer::init_puppet(server_options)

def wait_for_puppet_loading
  interation = 0
  loop do
    break if PuppetLanguageServer::PuppetHelper.default_functions_loaded? &&
             PuppetLanguageServer::PuppetHelper.default_types_loaded? &&
             PuppetLanguageServer::PuppetHelper.default_classes_loaded?
    sleep(1)
    interation += 1
    next if interation < 90
    raise <<-ERRORMSG
            Puppet has not be initialised in time:
            functions_loaded? = #{PuppetLanguageServer::PuppetHelper.default_functions_loaded?}
            types_loaded? = #{PuppetLanguageServer::PuppetHelper.default_types_loaded?}
            classes_loaded? = #{PuppetLanguageServer::PuppetHelper.default_classes_loaded?}
          ERRORMSG
  end
end

# Sidecar Protocol Helpers
def add_default_basepuppetobject_values!(value)
  value.key = :key
  value.calling_source = 'calling_source'
  value.source = 'source'
  value.line = 1
  value.char = 2
  value.length = 3
  value
end

def add_random_basepuppetobject_values!(value)
  value.key = ('key' + rand(1000).to_s).intern
  value.calling_source = 'calling_source' + rand(1000).to_s
  value.source = 'source' + rand(1000).to_s
  value.line = rand(1000)
  value.char = rand(1000)
  value.length = rand(1000)
  value
end

def random_sidecar_puppet_class
  result = add_random_basepuppetobject_values!(PuppetLanguageServer::Sidecar::Protocol::PuppetClass.new())
  result.doc = 'doc' + rand(1000).to_s
  result.parameters = {
    "attr_name1" => { :type => "Optional[String]", :doc => 'attr_doc1' },
    "attr_name2" => { :type => "String", :doc => 'attr_doc2' }
  }
  result
end

def random_sidecar_puppet_function
  result = add_random_basepuppetobject_values!(PuppetLanguageServer::Sidecar::Protocol::PuppetFunction.new())
  result.doc = 'doc' + rand(1000).to_s
  result.arity = rand(1000)
  result.type = ('type' + rand(1000).to_s).intern
  result.function_version = rand(1) + 3
  result
end

def random_sidecar_puppet_type
  result = add_random_basepuppetobject_values!(PuppetLanguageServer::Sidecar::Protocol::PuppetType.new())
  result.doc = 'doc' + rand(1000).to_s
  result.attributes = {
    :attr_name1 => { :type => :attr_type, :doc => 'attr_doc1', :required? => false, :isnamevar? => true },
    :attr_name2 => { :type => :attr_type, :doc => 'attr_doc2', :required? => false, :isnamevar? => false }
  }
  result
end

def random_sidecar_resource(typename = nil, title = nil)
  typename = 'randomtype' if typename.nil?
  title = rand(1000).to_s if title.nil?
  result = PuppetLanguageServer::Sidecar::Protocol::Resource.new()
  result.manifest = "#{typename} { '#{title}':\n  id => #{rand(1000).to_s}\n}"
  result
end

# Mock ojects
class MockConnection < PuppetEditorServices::SimpleServerConnectionBase
  def send_data(data)
    true
  end
end

class MockJSONRPCHandler < PuppetLanguageServer::JSONRPCHandler
  def initialize(options = {})
    super(options)

    @client_connection = MockConnection.new
  end

  def receive_data(data)
  end
end

class MockRelationshipGraph
  attr_accessor :vertices
  def initialize()
  end
end
