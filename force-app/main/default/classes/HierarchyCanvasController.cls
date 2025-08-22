@SuppressWarnings('PMD.CognitiveComplexity, PMD.OperationWithLimitsInLoop')
/**
 * @description Apex controller for Hierarchy Canvas component
 * @author AI Agent Studio
 */
public with sharing class HierarchyCanvasController {
    /**
     * @description Wrapper class for hierarchy node data
     */
    public class HierarchyNode {
        @AuraEnabled
        public String id { get; set; }
        @AuraEnabled
        public String type { get; set; }
        @AuraEnabled
        public String objectType { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String title { get; set; }
        @AuraEnabled
        public String subtitle { get; set; }
        @AuraEnabled
        public Boolean isExpanded { get; set; }
        @AuraEnabled
        public Boolean isCollapsible { get; set; }
        @AuraEnabled
        public Integer childCount { get; set; }
        @AuraEnabled
        public List<HierarchyNode> children { get; set; }
        @AuraEnabled
        public Object details { get; set; }

        public HierarchyNode() {
            this.children = new List<HierarchyNode>();
            this.isExpanded = false;
            this.isCollapsible = false;
            this.childCount = 0;
        }
    }

    /**
     * @description Get account hierarchy data with related objects from Salesforce
     * @param rootAccountId The root account ID to start the hierarchy from
     * @param configJson The configuration JSON string
     * @return List<HierarchyNode> The hierarchy structure with related objects
     */
    @AuraEnabled(cacheable=false)
    public static List<HierarchyNode> getHierarchyDetails(String rootAccountId, String configName) {
        List<HierarchyNode> hierarchy = new List<HierarchyNode>();

        try {
            // Get configuration from Custom Metadata
            HierarchyConfig config = getConfigFromMetadata(configName);

            if (String.isBlank(rootAccountId)) {
                // Get top-level records (no parent)
                hierarchy = getTopLevelRecords(config);
            } else {
                // Get specific record and build hierarchy
                hierarchy.add(buildRecordHierarchy(rootAccountId, config));
            }
            System.debug('Hierarchy: ' + JSON.serializePretty(hierarchy));
            return hierarchy;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving hierarchy: ' + e.getMessage());
        }
    }

    private static HierarchyConfig getConfigFromMetadata(String configName) {
        HierarchyConfig config = new HierarchyConfig();

        try {
            // Query Custom Metadata Type
            List<Hierarchy_Configuration__mdt> configs = [
                SELECT
                    Object_API_Name__c,
                    Parent_Field_API_Name__c,
                    Title_Field__c,
                    Subtitle_Field__c,
                    Field1_Label__c,
                    Field1_API_Name__c,
                    Field2_Label__c,
                    Field2_API_Name__c,
                    Include_Related_Objects__c,
                    Max_Records__c,
                    Icon_Name__c,
                    Related_Objects__c
                FROM Hierarchy_Configuration__mdt
                WHERE DeveloperName = :configName
                WITH SYSTEM_MODE
                LIMIT 1
            ];

            if (!configs.isEmpty()) {
                Hierarchy_Configuration__mdt configRecord = configs[0];

                config.objectApiName = configRecord.Object_API_Name__c;
                config.parentFieldApiName = configRecord.Parent_Field_API_Name__c;
                config.nameField = configRecord.Title_Field__c;
                config.subtitleField = configRecord.Subtitle_Field__c;
                config.field1Label = configRecord.Field1_Label__c;
                config.field1ApiName = configRecord.Field1_API_Name__c;
                config.field2Label = configRecord.Field2_Label__c;
                config.field2ApiName = configRecord.Field2_API_Name__c;
                config.includeRelatedObjects = configRecord.Include_Related_Objects__c;
                config.maxRecords = configRecord.Max_Records__c != null ? Integer.valueOf(configRecord.Max_Records__c) : null;
                config.iconName = configRecord.Icon_Name__c;

                // Parse related objects configuration
                if (String.isNotBlank(configRecord.Related_Objects__c)) {
                    try {
                        List<Object> relatedObjectsList = (List<Object>) JSON.deserializeUntyped(configRecord.Related_Objects__c);
                        config.relatedObjects = new List<RelatedObjectConfig>();

                        for (Object relatedObj : relatedObjectsList) {
                            Map<String, Object> relatedObjMap = (Map<String, Object>) relatedObj;
                            RelatedObjectConfig relatedConfig = new RelatedObjectConfig();

                            relatedConfig.objectApiName = (String) relatedObjMap.get('objectApiName');
                            relatedConfig.relationshipField = (String) relatedObjMap.get('relationshipField');
                            relatedConfig.nameField = (String) relatedObjMap.get('nameField');
                            relatedConfig.subtitleField = (String) relatedObjMap.get('subtitleField');
                            relatedConfig.iconName = (String) relatedObjMap.get('iconName');
                            relatedConfig.field1Label = (String) relatedObjMap.get('field1Label');
                            relatedConfig.field1ApiName = (String) relatedObjMap.get('field1ApiName');
                            relatedConfig.field2Label = (String) relatedObjMap.get('field2Label');
                            relatedConfig.field2ApiName = (String) relatedObjMap.get('field2ApiName');

                            config.relatedObjects.add(relatedConfig);
                        }
                    } catch (Exception e) {
                        System.debug('Error parsing related objects JSON: ' + e.getMessage());
                        config.relatedObjects = new List<RelatedObjectConfig>();
                    }
                } else {
                    config.relatedObjects = new List<RelatedObjectConfig>();
                }
            }
        } catch (Exception e) {
            System.debug('Error reading config from metadata: ' + e.getMessage());
        }

        // Set defaults if not provided
        if (String.isBlank(config.objectApiName)) {
            config.objectApiName = 'Account';
        }
        if (String.isBlank(config.parentFieldApiName)) {
            config.parentFieldApiName = 'ParentId';
        }
        if (String.isBlank(config.nameField)) {
            config.nameField = 'Name';
        }
        if (String.isBlank(config.subtitleField)) {
            config.subtitleField = 'Type';
        }
        if (config.includeRelatedObjects == null) {
            config.includeRelatedObjects = false;
        }
        if (config.maxRecords == null) {
            config.maxRecords = 1000;
        }
        if (String.isBlank(config.iconName)) {
            config.iconName = 'standard:account';
        }

        return config;
    }

    private static List<HierarchyNode> getTopLevelRecords(HierarchyConfig config) {
        List<HierarchyNode> hierarchy = new List<HierarchyNode>();

        // Escape field and object names to prevent SOQL injection
        String query = 'SELECT Id, ' + String.escapeSingleQuotes(config.nameField);
        if (config.subtitleField != config.nameField) {
            query += ', ' + String.escapeSingleQuotes(config.subtitleField);
        }
        if (String.isNotBlank(config.field1ApiName)) {
            query += ', ' + String.escapeSingleQuotes(config.field1ApiName);
        }
        if (String.isNotBlank(config.field2ApiName)) {
            query += ', ' + String.escapeSingleQuotes(config.field2ApiName);
        }
        query += ' FROM ' + String.escapeSingleQuotes(config.objectApiName);
        query += ' WHERE ' + String.escapeSingleQuotes(config.parentFieldApiName) + ' = null';
        query += ' LIMIT ' + Integer.valueOf(config.maxRecords);

        List<SObject> records = Database.query(query, AccessLevel.USER_MODE);
        System.debug('Top level records: ' + JSON.serializePretty(records));
        for (SObject record : records) {
            hierarchy.add(buildRecordHierarchy((String) record.get('Id'), config));
        }

        return hierarchy;
    }

    private static HierarchyNode buildRecordHierarchy(String recordId, HierarchyConfig config) {
        // Escape field and object names to prevent SOQL injection
        String query = 'SELECT Id, ' + String.escapeSingleQuotes(config.nameField);
        if (config.subtitleField != config.nameField) {
            query += ', ' + String.escapeSingleQuotes(config.subtitleField);
        }
        if (String.isNotBlank(config.field1ApiName)) {
            query += ', ' + String.escapeSingleQuotes(config.field1ApiName);
        }
        if (String.isNotBlank(config.field2ApiName)) {
            query += ', ' + String.escapeSingleQuotes(config.field2ApiName);
        }
        query += ' FROM ' + String.escapeSingleQuotes(config.objectApiName);
        query += ' WHERE Id = :recordId';

        SObject record = Database.query(query, AccessLevel.USER_MODE)[0];
        return convertToHierarchyNode(record, config);
    }

    private static HierarchyNode convertToHierarchyNode(SObject record, HierarchyConfig config) {
        HierarchyNode node = new HierarchyNode();
        node.id = (String) record.get('Id');
        node.name = (String) record.get(config.nameField);
        node.title = node.name;
        node.subtitle = (String) record.get(config.subtitleField);
        node.objectType = config.objectApiName;
        node.type = config.objectApiName;
        node.isCollapsible = true;
        node.isExpanded = false;
        node.children = new List<HierarchyNode>();

        // Set additional fields if configured
        Map<String, Object> details = new Map<String, Object>();

        if (String.isNotBlank(config.field1ApiName)) {
            Object fieldValue = record.get(config.field1ApiName);
            details.put('field1Label', config.field1Label);
            details.put('field1Value', fieldValue);
        }
        if (String.isNotBlank(config.field2ApiName)) {
            Object fieldValue = record.get(config.field2ApiName);
            details.put('field2Label', config.field2Label);
            details.put('field2Value', fieldValue);
        }

        // Add details to node if any fields are configured
        if (!details.isEmpty()) {
            node.details = details;
        }

        // Add child records if any
        getChildRecords(node, config);

        return node;
    }

    private static void getChildRecords(HierarchyNode parentNode, HierarchyConfig config) {
        // Get same-object child records
        getSameObjectChildren(parentNode, config);

        // Get related object records if configured
        if (config.includeRelatedObjects && config.relatedObjects != null && !config.relatedObjects.isEmpty()) {
            getRelatedObjectChildren(parentNode, config);
        }

        parentNode.childCount = parentNode.children.size();
    }

    private static void getSameObjectChildren(HierarchyNode parentNode, HierarchyConfig config) {
        // Escape field and object names to prevent SOQL injection
        String query = 'SELECT Id, ' + String.escapeSingleQuotes(config.nameField);
        if (config.subtitleField != config.nameField) {
            query += ', ' + String.escapeSingleQuotes(config.subtitleField);
        }
        if (String.isNotBlank(config.field1ApiName)) {
            query += ', ' + String.escapeSingleQuotes(config.field1ApiName);
        }
        if (String.isNotBlank(config.field2ApiName)) {
            query += ', ' + String.escapeSingleQuotes(config.field2ApiName);
        }
        query += ' FROM ' + String.escapeSingleQuotes(config.objectApiName);
        query += ' WHERE ' + String.escapeSingleQuotes(config.parentFieldApiName) + ' = :parentId';
        query += ' LIMIT 10';

        String parentId = parentNode.id;
        List<SObject> childRecords = Database.query(query, AccessLevel.USER_MODE);

        for (SObject childRecord : childRecords) {
            HierarchyNode childNode = convertToHierarchyNode(childRecord, config);
            parentNode.children.add(childNode);
        }
        parentNode.childCount = parentNode.children.size();
    }

    private static void getRelatedObjectChildren(HierarchyNode parentNode, HierarchyConfig config) {
        String parentId = parentNode.id;

        for (RelatedObjectConfig relatedConfig : config.relatedObjects) {
            // Build query for related object
            String query = 'SELECT Id, ' + String.escapeSingleQuotes(relatedConfig.nameField);

            if (String.isNotBlank(relatedConfig.subtitleField) && relatedConfig.subtitleField != relatedConfig.nameField) {
                query += ', ' + String.escapeSingleQuotes(relatedConfig.subtitleField);
            }
            if (String.isNotBlank(relatedConfig.field1ApiName)) {
                query += ', ' + String.escapeSingleQuotes(relatedConfig.field1ApiName);
            }
            if (String.isNotBlank(relatedConfig.field2ApiName)) {
                query += ', ' + String.escapeSingleQuotes(relatedConfig.field2ApiName);
            }

            query += ' FROM ' + String.escapeSingleQuotes(relatedConfig.objectApiName);
            query += ' WHERE ' + String.escapeSingleQuotes(relatedConfig.relationshipField) + ' = :parentId';
            query += ' LIMIT ' + (Integer.valueOf(relatedConfig.maxRecords) ?? 10); // Limit related objects to avoid too many results

            try {
                List<SObject> relatedRecords = Database.query(query, AccessLevel.USER_MODE);

                if (!relatedRecords.isEmpty()) {
                    // Create group node for this object type
                    HierarchyNode groupNode = createRelatedObjectGroupNode(relatedConfig, relatedRecords.size());

                    // Add individual records to the group
                    for (SObject relatedRecord : relatedRecords) {
                        HierarchyNode relatedNode = convertRelatedObjectToHierarchyNode(relatedRecord, relatedConfig);
                        groupNode.children.add(relatedNode);
                    }

                    groupNode.childCount = groupNode.children.size();
                    parentNode.children.add(groupNode);
                }
            } catch (Exception e) {
                System.debug('Error querying related object ' + relatedConfig.objectApiName + ': ' + e.getMessage());
            }
        }
    }

    private static HierarchyNode createRelatedObjectGroupNode(RelatedObjectConfig relatedConfig, Integer recordCount) {
        HierarchyNode groupNode = new HierarchyNode();
        groupNode.id = 'group_' + relatedConfig.objectApiName + '_' + System.currentTimeMillis();
        groupNode.name = getObjectPluralLabel(relatedConfig.objectApiName);
        groupNode.title = groupNode.name;
        groupNode.subtitle = recordCount + ' record' + (recordCount == 1 ? '' : 's');
        groupNode.objectType = 'ObjectGroup';
        groupNode.type = 'Group';
        groupNode.isCollapsible = true;
        groupNode.isExpanded = false;
        groupNode.children = new List<HierarchyNode>();
        groupNode.childCount = 0;

        return groupNode;
    }

    private static String getObjectPluralLabel(String objectApiName) {
        // Simple pluralization - in production you might want to use Schema.getGlobalDescribe()
        Map<String, String> pluralLabels = new Map<String, String>{
            'Opportunity' => 'Opportunities',
            'Contact' => 'Contacts',
            'Case' => 'Cases',
            'Asset' => 'Assets',
            'Account' => 'Accounts',
            'Lead' => 'Leads',
            'Task' => 'Tasks',
            'Event' => 'Events'
        };

        return pluralLabels.containsKey(objectApiName) ? pluralLabels.get(objectApiName) : objectApiName + 's';
    }

    private static HierarchyNode convertRelatedObjectToHierarchyNode(SObject record, RelatedObjectConfig relatedConfig) {
        HierarchyNode node = new HierarchyNode();
        node.id = (String) record.get('Id');
        node.name = (String) record.get(relatedConfig.nameField);
        node.title = node.name;
        node.subtitle = String.isNotBlank(relatedConfig.subtitleField)
            ? (String) record.get(relatedConfig.subtitleField)
            : relatedConfig.objectApiName;
        node.objectType = relatedConfig.objectApiName;
        node.type = relatedConfig.objectApiName;
        node.isCollapsible = false; // Related objects typically don't have children
        node.isExpanded = false;
        node.children = new List<HierarchyNode>();
        node.childCount = 0;

        // Set additional fields if configured
        Map<String, Object> details = new Map<String, Object>();

        if (String.isNotBlank(relatedConfig.field1ApiName)) {
            Object fieldValue = record.get(relatedConfig.field1ApiName);
            details.put('field1Label', relatedConfig.field1Label);
            details.put('field1Value', fieldValue);
        }
        if (String.isNotBlank(relatedConfig.field2ApiName)) {
            Object fieldValue = record.get(relatedConfig.field2ApiName);
            details.put('field2Label', relatedConfig.field2Label);
            details.put('field2Value', fieldValue);
        }

        // Add details to node if any fields are configured
        if (!details.isEmpty()) {
            node.details = details;
        }

        return node;
    }

    /**
     * @description Configuration class for hierarchy metadata
     */
    public class HierarchyConfig {
        public String objectApiName;
        public String parentFieldApiName;
        public String nameField;
        public String subtitleField;
        public String field1Label;
        public String field1ApiName;
        public String field2Label;
        public String field2ApiName;
        public Boolean includeRelatedObjects;
        public Integer maxRecords;
        public String iconName;
        public List<RelatedObjectConfig> relatedObjects;
    }

    public class RelatedObjectConfig {
        public String objectApiName;
        public String relationshipField;
        public String nameField;
        public String subtitleField;
        public String iconName;
        public String field1Label;
        public String field1ApiName;
        public String field2Label;
        public String field2ApiName;
        public Integer maxRecords;
    }
}