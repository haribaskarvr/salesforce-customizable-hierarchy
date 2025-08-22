# Customizable Hierarchy Component

A flexible Lightning Web Component that displays hierarchical data structures in Salesforce. This component allows you to visualize parent-child relationships for any Salesforce object with configurable display options.

## Features

- **Configurable Object Support**: Works with any Salesforce object that has parent-child relationships
- **Custom Metadata Configuration**: Easy setup through Custom Metadata Types without code changes
- **Flexible Display Options**: Configurable title fields, subtitle fields, and icons
- **Related Objects**: Option to include related object information in the hierarchy
- **Record Limits**: Configurable maximum number of records to display
- **Multi-Target Support**: Can be used on Record Pages, App Pages, and Home Pages

## Components

### Lightning Web Component
- **`hierarchyCanvas`**: The main LWC that renders the hierarchy visualization
  - Exposed for Lightning App Builder
  - Configurable through component properties
  - Supports Record, App, and Home page contexts

### Apex Controller
- **`HierarchyCanvasController`**: Server-side logic for data retrieval
- **`HierarchyCanvasControllerTest`**: Comprehensive test coverage

### Custom Metadata Type
- **`Hierarchy_Configuration__mdt`**: Configuration storage for different hierarchy setups
  - **Object_API_Name__c**: The object to display in hierarchy
  - **Parent_Field_API_Name__c**: Field that defines parent-child relationship
  - **Title_Field__c**: Primary display field for records
  - **Subtitle_Field__c**: Secondary display field for records
  - **Icon_Name__c**: SLDS icon name for visual representation
  - **Max_Records__c**: Maximum number of records to retrieve
  - **Include_Related_Objects__c**: Whether to include related object data
  - **Related_Objects__c**: Comma-separated list of related objects
  - **Field1_API_Name__c** & **Field1_Label__c**: Additional configurable field
  - **Field2_API_Name__c** & **Field2_Label__c**: Additional configurable field

## Installation

1. Deploy the metadata to your Salesforce org:
   ```bash
   sf project deploy start --source-dir force-app/main/default
   ```

2. Create a Custom Metadata record for your hierarchy configuration (example provided: `Account_Hierarchy`)

3. Add the component to your Lightning pages through the Lightning App Builder

## Configuration

### Setting Up a New Hierarchy

1. Navigate to **Setup > Custom Metadata Types > Hierarchy Configuration > Manage Records**
2. Click **New** to create a new configuration
3. Fill in the required fields:
   - **Label**: Display name for your configuration
   - **Developer Name**: API name (e.g., `Account_Hierarchy`)
   - **Object API Name**: The object to display (e.g., `Account`)
   - **Parent Field API Name**: The lookup field that defines hierarchy (e.g., `ParentId`)
   - **Title Field**: Primary field to display (e.g., `Name`)
   - Configure other optional fields as needed

### Using the Component

1. Edit a Lightning page in Lightning App Builder
2. Drag the **Hierarchy Canvas** component to your page
3. In the component properties, set the **Configuration Name** to match your Custom Metadata record's Developer Name
4. Save and activate your page

## Example Configuration

The included `Account_Hierarchy` configuration demonstrates a typical setup for displaying Account hierarchies with parent-child relationships.

## Development

### Prerequisites
- Salesforce CLI
- VS Code with Salesforce Extensions
- Access to a Salesforce org with Lightning Experience enabled

### Local Development
```bash
# Clone and navigate to project
cd Customizable_Hierarchy

# Authorize your org
sf org login web --alias myorg

# Deploy to org
sf project deploy start --source-dir force-app/main/default --target-org myorg

# Run tests
sf apex run test --test-level RunLocalTests --target-org myorg
```

## Troubleshooting

- Ensure the parent field specified in configuration exists and is accessible
- Verify that users have appropriate field-level security permissions
- Check that the Custom Metadata record Developer Name matches the component configuration
- Confirm the specified icon name exists in SLDS icon library

## Support

For questions or issues, please refer to the Salesforce Developer documentation or create an issue in your project repository.
