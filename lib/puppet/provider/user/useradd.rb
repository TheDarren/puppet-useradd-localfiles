require 'puppet/provider/nameservice/objectadd'

# Modified from the default useradd provider.
Puppet::Type.type(:user).provide :useradd, :parent => Puppet::Provider::NameService::ObjectAdd do
  desc "User management via `useradd` and its ilk.  Note that you will need to
    install Ruby's shadow password library (often known as `ruby-libshadow`)
    if you wish to manage user passwords."

  # NOTE: you may need to add your operatingsystem below to make this provider
  # work without puppet throwing a warning.
  defaultfor :operatingsystem => [ "CentOS", "Debian", "RedHat", "Ubuntu" ]
  commands :add => "useradd", :delete => "userdel", :modify => "usermod", :password => "chage"

  options :home, :flag => "-d", :method => :dir
  options :comment, :method => :gecos
  options :groups, :flag => "-G"
  options :password_min_age, :flag => "-m"
  options :password_max_age, :flag => "-M"

  verify :gid, "GID must be an integer" do |value|
    value.is_a? Integer
  end

  verify :groups, "Groups must be comma-separated" do |value|
    value !~ /\s/
  end

  has_features :manages_homedir, :allows_duplicates, :manages_expiry
  has_features :system_users unless %w{HP-UX Solaris}.include? Facter.value(:operatingsystem)

  has_features :manages_passwords, :manages_password_age if Puppet.features.libshadow?

  def check_allow_dup
    @resource.allowdupe? ? ["-o"] : []
  end

  def check_manage_home
    cmd = []
    if @resource.managehome?
      cmd << "-m"
    elsif %w{Fedora RedHat CentOS OEL OVS}.include?(Facter.value(:operatingsystem))
      cmd << "-M"
    end
    cmd
  end

  def check_manage_expiry
    cmd = []
    if @resource[:expiry]
      cmd << "-e #{@resource[:expiry]}"
    end

    cmd
  end

  def check_system_users
    if Puppet.version.start_with?("2.7") then
      if self.class.system_users? and resource.system?
        ["-r"]
      else
        []
      end
    end
  end

  def add_properties
    cmd = []
    Puppet::Type.type(:user).validproperties.each do |property|
      next if property == :ensure
      next if property.to_s =~ /password_.+_age/
      # the value needs to be quoted, mostly because -c might
      # have spaces in it
      if value = @resource.should(property) and value != ""
        cmd << flag(property) << value
      end
    end
    cmd
  end

  def addcmd
    cmd = [command(:add)]
    cmd += add_properties
    cmd += check_allow_dup
    cmd += check_manage_home
    cmd += check_manage_expiry
    if Puppet.version.start_with?("2.7") then
      cmd += check_system_users
    end
    cmd << @resource[:name]
  end
  
  def deletecmd
    cmd = [command(:delete)]
    cmd += @resource.managehome? ? ['-r'] : []
    cmd << @resource[:name]
  end

  def passcmd
    age_limits = [:password_min_age, :password_max_age].select { |property| @resource.should(property) }
    if age_limits.empty?
      nil
    else
      [command(:password),age_limits.collect { |property| [flag(property), @resource.should(property)]}, @resource[:name]].flatten
    end
  end

  def password_min_age
    if Puppet.features.libshadow?
      if ent = Shadow::Passwd.getspnam(@resource.name)
        return ent.sp_min
      end
    end
    :absent
  end

  def password_max_age
    if Puppet.features.libshadow?
      if ent = Shadow::Passwd.getspnam(@resource.name)
        return ent.sp_max
      end
    end
    :absent
  end

  # Retrieve the password using the Shadow Password library
  def password
    if Puppet.features.libshadow?
      if ent = Shadow::Passwd.getspnam(@resource.name)
        return ent.sp_pwdp
      end
    end
    :absent
  end

  # Retrieve what we can about our object
  def getinfo(refresh)
    if @objectinfo.nil? or refresh == true
      @objectinfo = nil
      if self.class.section.to_s == 'pw'
        pw = Struct::Passwd.new()
        # We're ignoring passwd from shadow.
        passwd_file = "/etc/passwd"
        File.open(passwd_file).each_line do |line|
          u = line.split(":")
          if @resource[:name] == u[0]
            pw.name = u[0]
            pw.passwd = u[1]
            pw.uid = u[2].to_i
            pw.gid = u[3].to_i
            pw.gecos = u[4]
            pw.dir = u[5]
            pw.shell = u[6].chomp
            @objectinfo = pw
          end
        end
      elsif self.class.section.to_s == 'gr'
        gr = Struct::Group.new()
        group_file = "/etc/group"
        File.open(group_file).each_line do |line|
          g = line.split(":")
          if @resource[:name] == g[0]
            gr.name = g[0]
            gr.passwd = g[1]
            gr.gid = g[2].chomp if g[2]
            gr.mem = g[3].chomp if g[3]
            @objectinfo = gr
          end
        end
      end
    end

    @objectinfo ? info2hash(@objectinfo) : nil
  end

  # The list of all groups the user is a member of.  Different
  # user mgmt systems will need to override this method.
  def groups
    groups = []

    user = @resource[:name]

    # Now iterate across all of the groups, adding each one our
    # user is a member of
    group_file = "/etc/group"
    File.open(group_file).each_line do |line|
      members = line.split(":")[3].split(",")
      groups << name if members.include? user
    end

    groups.join(",")
  end

  def self.instances
    names = []
    passwd_file = "/etc/passwd"
    begin
      f = File.open(passwd_file)
      f.each_line do |line|
        myname = line.split(":")[0]
        names << myname
        yield myname if block_given?
      end
    ensure
      f.close
    end
    objects = []
    names.each do |name|
       objects << new(:name => name, :ensure => :present)
    end

    objects
  end

  # Prefetching is necessary to use @property_hash inside any setter methods.
  # self.prefetch uses self.instances to gather an array of user instances
  # on the system, and then populates the @property_hash instance variable
  # with attribute data for the specific instance in question (i.e. it
  # gathers the 'is' values of the resource into the @property_hash instance
  # variable so you don't have to read from the system every time you need
  # to gather the 'is' values for a resource. The downside here is that
  # populating this instance variable for every resource on the system
  # takes time and front-loads your Puppet run.
  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

end

