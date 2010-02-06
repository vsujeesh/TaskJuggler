#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = NikuReport.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'reports/ReportBase'

class TaskJuggler

  class NikuProject

    attr_reader :name, :id, :tasks, :resources

    def initialize(id, name)
      @id = id
      @name = name
      @tasks = []
      @resources = {}
    end

  end

  class NikuResource

    attr_reader :id
    attr_accessor :sum

    def initialize(id)
      @id = id
      @sum = 0.0
    end

  end

  class NikuReport < ReportBase

    def initialize(report)
      super(report)

      # A Hash to store NikuProject objects by id
      @projects = {}

      # Resources total effort during the report period hashed by ClarityId
      @resourcesTotalEffort = {}
    end

    def generateIntermediateFormat
      super

      @scenarioIdx = a('scenarios')[0]

      computeResourceTotals
      collectProjects
      computeProjectTotals
    end

    def to_niku
      xml = XMLDocument.new
      xml << XMLComment.new('Generated by TaskJuggler')
      xml << (nikuDataBus =
              XMLElement.new('NikuDataBus',
                             'xmlns:xsi' =>
                             'http://www.w3.org/2001/XMLSchema-instance',
                             'xsi:noNamespaceSchemaLocation' =>
                             '../xsd/nikuxog_project.xsd'))
      nikuDataBus << XMLElement.new('Header', 'action' => 'write',
                                    'externalSource' => 'NIKU',
                                    'objectType' => 'project',
                                    'version' => '7.5.0')
      nikuDataBus << (projects = XMLElement.new('Projects'))

      timeFormat = '%Y-%m-%dT%H:%M:%S'
      @projects.each_value do |prj|
        projects << (project =
                     XMLElement.new('Project',
                                    'name' => prj.name,
                                    'projectID' => prj.id))
        project << (resources = XMLElement.new('Resources'))
        prj.resources.each_value do |res|
          resources << (resource =
                        XMLElement.new('Resource',
                                       'resourceID' => res.id,
                                       'defaultAllocation' => '0'))
          resource << (allocCurve = XMLElement.new('AllocCurve'))
          allocCurve << (XMLElement.new('Segment',
                                        'start' =>
                                        a('start').to_s(timeFormat),
                                        'finish' =>
                                        (a('end') - 1).to_s(timeFormat),
                                        'sum' => res.sum.to_s))
        end

        project << (customInfo = XMLElement.new('CustomInformation'))
        customInfo << XMLNamedText.new('amd_active', 'ColumnValue',
                                       'name' => 'amd_state')
        customInfo << XMLNamedText.new('amd_eng', 'ColumnValue',
                                       'name' => 'partition_code')
      end

      xml.to_s
    end

  private

    def computeResourceTotals
      # Prepare the resource list.
      resourceList = PropertyList.new(@project.resources)
      resourceList.setSorting(@report.get('sortResources'))
      resourceList = filterResourceList(resourceList, nil,
                                        @report.get('hideResource'),
                                        @report.get('rollupResource'))

      resourceList.each do |resource|
        next if (resourceId = resource.get('ClarityRID')).nil?

        # Prepare a template for the Query we will use to get all the data.
        queryAttrs = { 'project' => @project,
                       'property' => resource,
                       'scopeProperty' => nil,
                       'scenarioIdx' => @scenarioIdx,
                       'loadUnit' => a('loadUnit'),
                       'numberFormat' => a('numberFormat'),
                       'timeFormat' => a('timeFormat'),
                       'currencyFormat' => a('currencyFormat'),
                       'start' => a('start'), 'end' => a('end'),
                       'costAccount' => a('costAccount'),
                       'revenueAccount' => a('revenueAccount') }

        query = Query.new(queryAttrs)
        query.attributeId = 'effort'
        query.process

        @resourcesTotalEffort[resourceId] = query.to_num
      end
    end

    def collectProjects
      # Prepare the task list.
      taskList = PropertyList.new(@project.tasks)
      taskList.setSorting(@report.get('sortTasks'))
      taskList = filterTaskList(taskList, nil, @report.get('hideTask'),
                                @report.get('rollupTask'))


      taskList.each do |task|
        next unless task.leaf? ||
                    task['assignedresources', @scenarioIdx].empty?

        id = task.get('ClarityPID')
        if (project = @projects[id]).nil?
          project = NikuProject.new(id, task.get('ClarityPName'))
          @projects[id] = project
        end
        project.tasks << task
      end
    end

    def computeProjectTotals
      @projects.each_value do |project|
        project.tasks.each do |task|
          task['assignedresources', @scenarioIdx].each do |resource|
            # Prepare a template for the Query we will use to get all the data.
            queryAttrs = { 'project' => @project,
                           'property' => task,
                           'scopeProperty' => resource,
                           'scenarioIdx' => @scenarioIdx,
                           'loadUnit' => a('loadUnit'),
                           'numberFormat' => a('numberFormat'),
                           'timeFormat' => a('timeFormat'),
                           'currencyFormat' => a('currencyFormat'),
                           'start' => a('start'), 'end' => a('end'),
                           'costAccount' => a('costAccount'),
                           'revenueAccount' => a('revenueAccount') }

            query = Query.new(queryAttrs)
            query.attributeId = 'effort'
            query.process

            resourceId = resource.get('ClarityRID')
            if (resourceRecord = project.resources[resourceId]).nil?
              resourceRecord = NikuResource.new(resourceId)
              project.resources[resourceId] = resourceRecord
            end
            resourceRecord.sum += query.to_num
          end
        end
      end
    end

  end

end
