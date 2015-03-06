# encoding: utf-8

# File:
#	modules/AutoinstClass.ycp
#
# Module:
#	AutoinstClass
#
# Summary:
#	This module handles the configuration for auto-installation
#
# Authors:
#	Anas Nashif <nashif@suse.de>
#
# $Id$
require "yast"

module Yast
  class AutoinstClassClass < Module
    include Yast::Logger

    attr_accessor :merge_xslt_path

    def main

      Yast.import "AutoinstConfig"
      Yast.import "XML"
      Yast.import "Summary"
      Yast.include self, "autoinstall/xml.rb"

      @classDir = AutoinstConfig.classDir
      @ClassConf = "/etc/autoinstall"
      @merge_xslt_path = "/usr/share/autoinstall/xslt/merge.xslt"
      @profile_conf = []
      @Profiles = []
      @Classes = []
      @deletedClasses = []
      @confs = []
      @class_file = "classes.xml"
      @classPath = File.join(@classDir, @class_file)

      AutoinstClass()
    end

    # find a profile path
    # @param string profile name
    # @return [String] profile Path
    def findPath(name, class_)
      result = @confs.find { |c| c['name'] == name && c['class'] == class_ }
      result ||= { 'class' => '', 'name' => 'default' }
      File.join(@classDir, result['class'], result['name'])
    end

    # Read classes
    def Read
      if SCR.Read(path(".target.size"), @classPath) != -1
        # TODO: use XML module
        classes_map = Convert.to_map(SCR.Read(path(".xml"), @classPath))
        @Classes = (classes_map && classes_map['classes']) || []
      else
        @Classes = []
      end
      nil
    end

    #     we are doing some compatibility fixes here and move
    #     from one /etc/autoinstall/classes.xml to multiple
    #     classes.xml files, one for each repository
    def Compat
      if !class_file_exists? && compat_class_file_exists?
        log.info "Compat: #{@classPath} no found but #{compat_class_file} exists"
        new_classes_map = { 'classes' => read_old_classes }
        log.info "creating #{new_classes_map}"
        XML.YCPToXMLFile(:class, new_classes_map, @classPath)
      end
      nil
    end

    # Change the directory and read the class definitions
    #
    # @param [String] Path of the new directory
    # @return nil
    # @see class_dir=
    def classDirChanged(newdir)
      self.class_dir = newdir
      Compat()
      Read()
      nil
    end

    # Change the directory of classes definitions.
    #
    # AutoinstConfig#classDir= is called to set the new value
    # in the configuration. It does not check if the directory
    # exists or is accessible.
    #
    # @return [String] path of the new directory.
    def class_dir=(newdir)
      AutoinstConfig.classDir = newdir
      @classDir = newdir
      @classPath = File.join(@classDir, @class_file)
      newdir
    end

    # Constructor
    # @return void

    def AutoinstClass
      classSetup
      Compat()
      Read()
      nil
    end

    # Merge classes
    #
    def MergeClasses(configuration, base_profile, resultFileName)
      dontmerge_str = ""
      AutoinstConfig.dontmerge.each_with_index do |dm, i|
        dontmerge_str << " --param dontmerge#{i+1} \"'#{dm}'\" "
      end
      merge_command =
        "/usr/bin/xsltproc --novalid --param replace \"'false'\" #{dontmerge_str} --param with " \
        "\"'#{findPath(configuration['name'], configuration['class'])}'\"  " \
        "--output #{File.join(AutoinstConfig.tmpDir, resultFileName)}  " \
        "#{@merge_xslt_path} #{base_profile} "

      log.info "Merge command: #{merge_command}"
      out = SCR.Execute(path(".target.bash_output"), merge_command, {})
      log.info "Merge stdout: #{out['stdout']}, stderr: #{out['stderr']}"
      out
    end

    # Read files from class directories
    # @return [void]
    def Files
      @confs = []
      @Classes.each do |class_|
        class_name_ = class_['name'] || 'xxx'
        files_path = File.join(@classDir, class_name_)
        files = Convert.convert(SCR.Read(path('.target.dir'), files_path),
          :from => "any", :to   => "list <string>")

        next if files.nil?

        log.info "Files in class #{class_name_}: #{files}"
        new_confs = files.map { |f| { 'class' => class_name_, 'name' => f  }  }
        log.info "Configurations: #{new_confs}"
        @confs.concat(new_confs)
      end
      log.info "Configurations: #{@confs}"
      nil
    end

    # Save Class definitions
    def Save
      @deletedClasses.each do |c|
        to_del = "/bin/rm -rf #{File.join(AutoinstConfig.classDir, c)}"
        SCR.Execute(path(".target.bash"), to_del)
      end
      @deletedClasses = []
      tmp = { "classes" => @Classes }
      log.debug "saving classes: #{@classPath}"
      XML.YCPToXMLFile(:class, tmp, @classPath)
    end


    # Import configuration
    # @params [Array<Hash>] settings Configuration
    # @return true
    def Import(settings)
      @profile_conf = deep_copy(settings)
      true
    end

    # Export configuration
    # @return [Array<Hash>] Copy of the configuration
    def Export
      deep_copy(@profile_conf)
    end

    # Return configuration summary
    # @return [String] Configuration summary
    def Summary
      summary = ""
      @profile_conf.each do |conf|
        summary = Summary.AddHeader(summary, conf['class_name'] || 'None')
        summary = Summary.AddLine(summary, conf['configuration'] || 'None')
      end
      summary.empty? ? Summary.NotConfigured : summary
    end

    publish :variable => :classDir, :type => "string"
    publish :variable => :ClassConf, :type => "string"
    publish :variable => :profile_conf, :type => "list <map>"
    publish :variable => :Profiles, :type => "list"
    publish :variable => :Classes, :type => "list <map>"
    publish :variable => :deletedClasses, :type => "list <string>"
    publish :variable => :confs, :type => "list <map>"
    publish :function => :findPath, :type => "string (string, string)"
    publish :function => :Read, :type => "void ()"
    publish :function => :Compat, :type => "void ()"
    publish :function => :classDirChanged, :type => "void (string)"
    publish :function => :AutoinstClass, :type => "void ()"
    publish :function => :MergeClasses, :type => "map (map, string, string)"
    publish :function => :Files, :type => "void ()"
    publish :function => :Save, :type => "boolean ()"
    publish :function => :Import, :type => "boolean (list <map>)"
    publish :function => :Export, :type => "list <map> ()"
    publish :function => :Summary, :type => "string ()"

    private

    # Checks if a classes.xml exists
    # @return [true,false] Returns true when present (false otherwise).
    def class_file_exists?
      SCR.Read(path(".target.size"), @classPath) > 0
    end

    # Checks if an old classes.xml exists
    # @return [true,false] Returns true when present (false otherwise).
    # @see compat_class_file
    def compat_class_file_exists?
      SCR.Read(path(".target.size"), compat_class_file) > 0
    end

    # Returns the path of the old classes.xml file
    # By default, it is called /etc/autoinstall/classes.xml.
    # @return [String] Path to the old classes.xml file.
    def compat_class_file
      File.join(@ClassConf, @class_file)
    end

    # Builds a map of classes to import from /etc/autoinstall/classes.xml
    # @return [Array<Hash>] Classes defined in the file.
    def read_old_classes
      old_classes_map = Convert.to_map(SCR.Read(path('.xml'), compat_class_file))
      old_classes = old_classes_map['classes'] || []
      old_classes.each_with_object([]) do |class_, new_classes|
        class_path_ = File.join(@classDir, class_['name'] || '')
        log.info "looking for #{class_path_}"
        new_classes << class_ unless SCR.Read(path(".target.dir"), class_path_).nil?
      end
    end
  end

  AutoinstClass = AutoinstClassClass.new
  AutoinstClass.main
end
