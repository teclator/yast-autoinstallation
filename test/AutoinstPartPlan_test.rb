#!/usr/bin/env rspec

require_relative "test_helper"
require "yaml"

Yast.import "AutoinstPartPlan"
Yast.import "Profile"
Yast.import "ProductFeatures"

describe Yast::AutoinstPartPlan do
  let(:target_map_path) { File.join(FIXTURES_PATH, "storage", "nfs_root.yml") }
  let(:target_map_clone) { File.join(FIXTURES_PATH, "storage", "target_clone.yml") }

  describe "#read partition target" do

    it "exporting nfs root partition" do
      target_map = YAML.load_file(target_map_path)

      expect(Yast::Storage).to receive(:GetTargetMap).and_return(target_map)
      expect(Yast::AutoinstPartPlan.Read).to eq(true)
      expect(Yast::AutoinstPartPlan.Export).to eq(
         [{"type"=>:CT_NFS,
            "partitions"=>[{"type"=>:nfs,
              "device"=>"192.168.4.1:/srv/nfsroot/sles12sp1",
              "mount"=>"/",
              "fstopt"=>"minorversion=1"}],
            "device"=>"/dev/nfs", "use"=>"all"}
         ]
        )
    end

    it "ignoring not needed devices" do
      target_map = YAML.load_file(target_map_clone)

      expect(Yast::Storage).to receive(:GetTargetMap).and_return(target_map)
      expect(Yast::AutoinstPartPlan.Read).to eq(true)
      export = Yast::AutoinstPartPlan.Export.select { |d| d.key?("skip_list") }

      expect(export[0]).to include("initialize" => true)
      skip_list = export[0]["skip_list"]
      expect(skip_list).to all(include("skip_key" => "device"))
      expect(skip_list).to all(include("skip_value" => /\/dev\//))
    end
  end

  describe "#Export" do
    let(:target_map) { YAML.load_file(File.join(FIXTURES_PATH, "storage", "subvolumes.yml")) }

    before do
      allow(Yast::Storage).to receive(:GetTargetMap).and_return(target_map)
      Yast::AutoinstPartPlan.Read
    end

    it "includes found subvolumes" do
      exported = Yast::AutoinstPartPlan.Export
      subvolumes = exported.first["partitions"].first["subvolumes"]
      expect(subvolumes).to eq([
        { "path" => "@", "copy_on_write" => true},
        { "path" => "home", "copy_on_write" => true },
        { "path" => "var/log", "copy_on_write" => true },
        { "path" => "var/lib/pgsql", "copy_on_write" => true },
        { "path" => "myvol", "copy_on_write" => false },
      ])
    end

    it "does not include snapshots" do
      exported = Yast::AutoinstPartPlan.Export
      subvolumes = exported.first["partitions"].first["subvolumes"]
      snapshots = subvolumes.select { |s| s.include?("snapshot") }
      expect(snapshots).to be_empty
    end
  end
end
