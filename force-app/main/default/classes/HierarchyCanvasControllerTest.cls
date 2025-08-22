@IsTest
private class HierarchyCanvasControllerTest {
    @TestSetup
    static void setupTestData() {
        // Create test accounts with hierarchy
        Account parentAccount = new Account(Name = 'Parent Account', Type = 'Customer', Industry = 'Technology');
        insert parentAccount;

        Account childAccount1 = new Account(Name = 'Child Account 1', Type = 'Partner', Industry = 'Healthcare', ParentId = parentAccount.Id);

        Account childAccount2 = new Account(Name = 'Child Account 2', Type = 'Customer', Industry = 'Finance', ParentId = parentAccount.Id);

        insert new List<Account>{ childAccount1, childAccount2 };

        // Create related contacts
        Contact contact1 = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@test.com',
            AccountId = parentAccount.Id,
            Title = 'CEO'
        );

        Contact contact2 = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            Email = 'jane.smith@test.com',
            AccountId = childAccount1.Id,
            Title = 'CTO'
        );

        insert new List<Contact>{ contact1, contact2 };

        // Create related opportunities
        Opportunity opp1 = new Opportunity(
            Name = 'Test Opportunity 1',
            AccountId = parentAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 100000
        );

        Opportunity opp2 = new Opportunity(
            Name = 'Test Opportunity 2',
            AccountId = childAccount1.Id,
            StageName = 'Qualification',
            CloseDate = Date.today().addDays(60),
            Amount = 50000
        );

        insert new List<Opportunity>{ opp1, opp2 };
    }

    @IsTest
    static void testGetHierarchyDetailsWithValidAccountId() {
        // Get test account
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Parent Account' LIMIT 1];

        Test.startTest();
        List<HierarchyCanvasController.HierarchyNode> result = HierarchyCanvasController.getHierarchyDetails(testAccount.Id, 'Account_Hierarchy');
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Should return one root node');

        HierarchyCanvasController.HierarchyNode rootNode = result[0];
        System.assertEquals(testAccount.Id, rootNode.id, 'Root node ID should match');
        System.assertEquals('Parent Account', rootNode.name, 'Root node name should match');
        System.assertEquals('Account', rootNode.objectType, 'Object type should be Account');
        System.assertEquals(true, rootNode.isCollapsible, 'Root node should be collapsible');
        System.assertEquals(4, rootNode.childCount, 'Should have 4 child accounts');
        System.assertEquals(4, rootNode.children.size(), 'Children list should have 4 items');
    }

    @IsTest
    static void testGetHierarchyDetailsWithNullAccountId() {
        Test.startTest();
        List<HierarchyCanvasController.HierarchyNode> result = HierarchyCanvasController.getHierarchyDetails(null, 'Account_Hierarchy');
        Test.stopTest();

        // Should return top-level accounts (those without parents)
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Should return one top-level account');

        HierarchyCanvasController.HierarchyNode rootNode = result[0];
        System.assertEquals('Parent Account', rootNode.name, 'Should be the parent account');
    }

    @IsTest
    static void testGetHierarchyDetailsWithEmptyAccountId() {
        Test.startTest();
        List<HierarchyCanvasController.HierarchyNode> result = HierarchyCanvasController.getHierarchyDetails('', 'Account_Hierarchy');
        Test.stopTest();

        // Should return top-level accounts
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Should return one top-level account');
    }

    @IsTest
    static void testGetHierarchyDetailsWithInvalidAccountId() {
        Test.startTest();
        try {
            HierarchyCanvasController.getHierarchyDetails('001000000000000', 'Account_Hierarchy');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception'), 'Should throw AuraHandledException with appropriate message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetHierarchyDetailsWithInvalidConfigName() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Parent Account' LIMIT 1];

        Test.startTest();
        List<HierarchyCanvasController.HierarchyNode> result = HierarchyCanvasController.getHierarchyDetails(testAccount.Id, 'Invalid_Config');
        Test.stopTest();

        // Should use default configuration
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Should return one node with default config');

        HierarchyCanvasController.HierarchyNode rootNode = result[0];
        System.assertEquals(testAccount.Id, rootNode.id, 'Root node ID should match');
    }

    @IsTest
    static void testHierarchyNodeConstructor() {
        Test.startTest();
        HierarchyCanvasController.HierarchyNode node = new HierarchyCanvasController.HierarchyNode();
        Test.stopTest();

        // Test default values
        System.assertNotEquals(null, node.children, 'Children list should be initialized');
        System.assertEquals(0, node.children.size(), 'Children list should be empty');
        System.assertEquals(false, node.isExpanded, 'Should not be expanded by default');
        System.assertEquals(false, node.isCollapsible, 'Should not be collapsible by default');
        System.assertEquals(0, node.childCount, 'Child count should be 0');
    }

    @IsTest
    static void testHierarchyWithRelatedObjects() {
        // This test would require custom metadata setup for related objects
        // For now, testing the basic functionality without related objects
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Parent Account' LIMIT 1];

        Test.startTest();
        List<HierarchyCanvasController.HierarchyNode> result = HierarchyCanvasController.getHierarchyDetails(testAccount.Id, 'Account_Hierarchy');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');

        HierarchyCanvasController.HierarchyNode rootNode = result[0];
        System.assertNotEquals(null, rootNode.children, 'Children should not be null');

        // Verify child nodes
        for (HierarchyCanvasController.HierarchyNode child : rootNode.children) {
            System.assertNotEquals(null, child.id, 'Child ID should not be null');
            System.assertNotEquals(null, child.name, 'Child name should not be null');
        }
    }

    @IsTest
    static void testConfigurationDefaults() {
        // Test that default configuration values are applied when metadata is not found
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Parent Account' LIMIT 1];

        Test.startTest();
        List<HierarchyCanvasController.HierarchyNode> result = HierarchyCanvasController.getHierarchyDetails(testAccount.Id, 'NonExistent_Config');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Should return one node');

        HierarchyCanvasController.HierarchyNode rootNode = result[0];
        System.assertEquals('Parent Account', rootNode.name, 'Should use Name field as default');
        System.assertEquals('Account', rootNode.objectType, 'Should default to Account object');
    }

    @IsTest
    static void testLargeHierarchy() {
        // Create additional test data for large hierarchy
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Parent Account' LIMIT 1];

        List<Account> additionalAccounts = new List<Account>();
        for (Integer i = 3; i <= 12; i++) {
            additionalAccounts.add(new Account(Name = 'Child Account ' + i, Type = 'Customer', ParentId = parentAccount.Id));
        }
        insert additionalAccounts;

        Test.startTest();
        List<HierarchyCanvasController.HierarchyNode> result = HierarchyCanvasController.getHierarchyDetails(parentAccount.Id, 'Account_Hierarchy');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');

        HierarchyCanvasController.HierarchyNode rootNode = result[0];
        System.assertEquals(rootNode.children.size(), rootNode.childCount, 'Child count should match children size');
    }

    @IsTest
    static void testNodeDetailsPopulation() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Parent Account' LIMIT 1];

        Test.startTest();
        List<HierarchyCanvasController.HierarchyNode> result = HierarchyCanvasController.getHierarchyDetails(testAccount.Id, 'Account_Hierarchy');
        Test.stopTest();

        HierarchyCanvasController.HierarchyNode rootNode = result[0];

        // Verify basic node properties
        System.assertEquals(testAccount.Id, rootNode.id, 'ID should match');
        System.assertEquals('Parent Account', rootNode.title, 'Title should match name');
        System.assertNotEquals(null, rootNode.subtitle, 'Subtitle should not be null');
        System.assertEquals(true, rootNode.isCollapsible, 'Should be collapsible');
        System.assertEquals(false, rootNode.isExpanded, 'Should not be expanded by default');
    }

    @IsTest
    static void testExceptionHandling() {
        Test.startTest();
        try {
            // Pass an invalid ID format to trigger an exception
            HierarchyCanvasController.getHierarchyDetails('invalid_id_format', 'Account_Hierarchy');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception'), 'Should contain error message');
        }
        Test.stopTest();
    }
}