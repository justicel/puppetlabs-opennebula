require 'rexml/document'
require 'tempfile'
require 'erb'

Puppet::Type.type(:onevm).provide(:onevm) do
  desc "onevm provider"

  commands :onevm => "onevm"

  # Create a VM with onevm by passing in a temporary template.
  def create
    file = Tempfile.new("onevm-#{resource[:name].to_s}")

    os_array = []
    ["arch","kernel","initrd","root","kernel_cmd","bootloader","boot"].each { |k|
      sym = "os_#{k.to_s}".to_sym
      if resource[sym] then
        os_array << "#{k.to_s.upcase} = #{resource[sym]}"
      end
    }

    debug("Start building up template for create command")
    template = ERB.new <<-EOF
NAME = "<%= resource[:name].to_s %>"
MEMORY = <%= resource[:memory].to_s %>
CPU = <%= resource[:cpu].to_s %>
VCPU = <%= resource[:vcpu].to_s %>

OS = [ <%= os_array.join(", \n") %> ]

<% 
resource[:disks].each { |disk| 
  disk_array = [] 
  next if !disk.is_a?(Hash)
  next if disk.size < 1
  disk.each { |key,value|
    disk_array << key.to_s.upcase + " = " + value.to_s
  } %>
DISK = [ <%= disk_array.join(", \n") %> ]
<%
} 

resource[:nics].each { |nic|
  nic_array = []
  next if !nic.is_a?(Hash)
  next if nic.size < 1
  nic.each { |key,value|
    nic_array << key.to_s.upcase + " = " + value.to_s
  } %>
NIC = [ <%= nic_array.join(", \n") %> ]
<%
}

graph_array = []
["type","listen","port","passwd","keymap"].each { |param|
  res = ("graphics_"+param.to_s).to_sym
  if resource[res] then
    graph_array << param.to_s.upcase + " = " + resource[res]
  end
}
%>
GRAPHICS = [ <%= graph_array.join(", \n") %> ]

<% 
if resource[:context] then
  context_array = []
  resource[:context].each { |key,value|
    context_array << key.to_s.upcase + ' = "' + value.to_s + '"'
  } %>
CONTEXT = [ <%= context_array.join(", \n") %> ]
<%
end
%>
EOF

    debug("Created template, lets try and parse it")
    tempfile = template.result(binding)
    debug("template is:\n#{tempfile}")
    file.write(tempfile)
    file.close
    onevm "create", file.path
  end

  # Destroy a VM using onevm delete
  def destroy
    onevm "delete", resource[:name]
  end

  # Return a list of existing VM's using the onevm list -x command
  def self.onevm_list
    xml = REXML::Document.new(`onevm list -x`)
    onevm = []
    xml.elements.each("VM_POOL/VM/NAME") do |element|
      onevm << element.text
    end
    onevm
  end

  # Check if a VM exists by scanning the onevm list
  def exists?
    self.class.onevm_list().include?(resource[:name])
  end

  # Return the full hash of all existing onevm resources
  def self.instances
    instances = []
    onevm_list.each do |vm|
      hash = {}

      # Obvious resource attributes
      hash[:provider] = self.name.to_s
      hash[:name] = vm

      # Open onevm xml output using REXML
      xml = REXML::Document.new(`onevm show -x #{vm}`)

      # Traverse the XML document and populate the common attributes
      xml.elements.each("VM/MEMORY") { |element|
        hash[:memory] = element.text
      }
      xml.elements.each("VM/CPU") { |element|
        hash[:cpu] = element.text
      }
      xml.elements.each("VM/VCPU") { |element|
        hash[:vcpu] = element.text
      }

      instances << new(hash)
    end

    instances
  end
end
