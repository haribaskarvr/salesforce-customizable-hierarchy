import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHierarchyDetails from '@salesforce/apex/HierarchyCanvasController.getHierarchyDetails';
import sldsIcons from '@salesforce/resourceUrl/sldsIcons';

const SVG_NAMESPACE = 'http://www.w3.org/2000/svg';
const XLINK_NAMESPACE = 'http://www.w3.org/1999/xlink';
const XLINK_HREF = 'xlink:href';

export default class HierarchyCanvas extends NavigationMixin(LightningElement) {
    @track treeData = [];
    isLoading = false;

    // Pan and zoom state
    panX = 0;
    panY = 0;
    zoomLevel = 1;
    minZoom = 0.25;
    maxZoom = 3;
    isDragging = false;
    lastMouseX = 0;
    lastMouseY = 0;
    loadHierarchyCalled = false;
    _configurationName = 'Account_Hierarchy';
    _recordId = null;

    // Configuration property
    @api set configurationName(value) {
        if (value) {
            this._configurationName = value;
        }
    }
    get configurationName() {
        return this._configurationName;
    }

    @api
    set recordId(value) {
        if (value) {
            this._recordId = value;
        }
    }

    get recordId() {
        return this._recordId;
    }

    // Computed properties for template
    get zoomPercentage() {
        return Math.round(this.zoomLevel * 100);
    }

    // Layout for D3.js SVG rendering
    get flatNodes() {
        let result = [];
        let currentY = 50;
        const HORIZONTAL_SPACING = 320; // Space between levels (increased for wider nodes)
        const VERTICAL_SPACING = 140;   // Space between nodes (increased to prevent overlap)

        const layout = (nodes, depth, parentExpanded = true) => {
            for (let node of nodes) {
                // Only show nodes if parent is expanded (or if this is root level)
                if (parentExpanded || depth === 0) {
                    const nodeX = 50 + (depth * HORIZONTAL_SPACING);
                    const nodeY = currentY;

                    // Add all node properties directly
                    result.push({
                        ...node, // Spread all original node properties
                        x: nodeX,
                        y: nodeY,
                        depth: depth,
                        isHighlighted: false
                    });

                    currentY += VERTICAL_SPACING;

                    // Layout children only if this node is expanded
                    if (node.children && node.children.length > 0) {
                        const isNodeExpanded = node.isExpanded !== false; // Default to expanded if not specified
                        layout(node.children, depth + 1, isNodeExpanded);
                    }
                }
            }
        };

        if (this.treeData && this.treeData.length > 0) {
            layout(this.treeData, 0);
        }
        return result;
    }

    // Load hierarchy for current record
    async loadHierarchy() {
        if (!this.recordId || !this.configurationName) {
            return;
        }
        this.loadHierarchyCalled = true;
        try {
            const data = await getHierarchyDetails({
                rootAccountId: this.recordId,
                configName: this.configurationName
            });
            this.treeData = data || [];
            this.renderD3Hierarchy();
        } catch (error) {
            console.error('Error loading account hierarchy:', error);
            this.showToast('Error', 'Failed to load account hierarchy: ' + error.body?.message, 'error');
        }
    }

    renderedCallback() {
        if (!this.svgElement) {
            this.initializeD3SVG();
        }
        if (this.treeData && this.treeData.length > 0) {
            this.renderD3Hierarchy();
        }

        if (!this.loadHierarchyCalled) {
            this.loadHierarchy();
        }
    }

    initializeD3SVG() {
        const canvas = this.template.querySelector('.hierarchy-canvas');
        if (!canvas) {
            console.log('Canvas element not found');
            return;
        }

        // Remove existing SVG if it exists
        const existingSvg = canvas.querySelector('svg.d3-canvas');
        if (existingSvg) {
            canvas.removeChild(existingSvg);
        }

        // Create SVG using D3-style approach
        this.svgElement = document.createElementNS(SVG_NAMESPACE, 'svg');
        this.svgElement.setAttribute('class', 'd3-canvas');
        this.svgElement.setAttribute('width', '100%');
        this.svgElement.setAttribute('height', '100%');
        this.svgElement.setAttribute('viewBox', '0 0 2000 1200');
        this.svgElement.style.position = 'absolute';
        this.svgElement.style.top = '0';
        this.svgElement.style.left = '0';
        this.svgElement.style.pointerEvents = 'all';
        this.svgElement.style.background = 'transparent';

        // Create defs for reusable elements
        const defs = document.createElementNS(SVG_NAMESPACE, 'defs');
        this.svgElement.appendChild(defs);


        // Create defs for filters
        const glowFilter = document.createElementNS(SVG_NAMESPACE, 'filter');
        glowFilter.setAttribute('id', 'glow');
        const gaussianBlur = document.createElementNS(SVG_NAMESPACE, 'feGaussianBlur');
        gaussianBlur.setAttribute('stdDeviation', '2');
        gaussianBlur.setAttribute('result', 'coloredBlur');
        const feMerge = document.createElementNS(SVG_NAMESPACE, 'feMerge');
        const feMergeNode1 = document.createElementNS(SVG_NAMESPACE, 'feMergeNode');
        feMergeNode1.setAttribute('in', 'coloredBlur');
        const feMergeNode2 = document.createElementNS(SVG_NAMESPACE, 'feMergeNode');
        feMergeNode2.setAttribute('in', 'SourceGraphic');
        feMerge.appendChild(feMergeNode1);
        feMerge.appendChild(feMergeNode2);
        glowFilter.appendChild(gaussianBlur);
        glowFilter.appendChild(feMerge);
        defs.appendChild(glowFilter);
        this.svgElement.appendChild(defs);


        // Create main group for transformations
        this.mainGroup = document.createElementNS(SVG_NAMESPACE, 'g');
        this.mainGroup.setAttribute('class', 'main-canvas');
        this.svgElement.appendChild(this.mainGroup);

        // Create layers
        this.connectionsLayer = document.createElementNS(SVG_NAMESPACE, 'g');
        this.connectionsLayer.setAttribute('class', 'connections-layer');
        this.nodesLayer = document.createElementNS(SVG_NAMESPACE, 'g');
        this.nodesLayer.setAttribute('class', 'nodes-layer');

        this.mainGroup.appendChild(this.connectionsLayer);
        this.mainGroup.appendChild(this.nodesLayer);

        canvas.appendChild(this.svgElement);

        // Add event listeners
        this.svgElement.addEventListener('mousedown', this.handleCanvasMouseDown.bind(this));
        this.svgElement.addEventListener('mousemove', this.handleCanvasMouseMove.bind(this));
        this.svgElement.addEventListener('mouseup', this.handleCanvasMouseUp.bind(this));
        this.svgElement.addEventListener('mouseleave', this.handleCanvasMouseLeave.bind(this));
        this.svgElement.addEventListener('wheel', this.handleCanvasWheel.bind(this));
    }

    renderD3Hierarchy() {
        if (!this.mainGroup || !this.treeData) return;

        // Apply transform
        this.mainGroup.setAttribute('transform',
            `translate(${this.panX}, ${this.panY}) scale(${this.zoomLevel})`);

        // Clear existing content
        this.connectionsLayer.innerHTML = '';
        this.nodesLayer.innerHTML = '';

        // Ensure we have the DOM elements
        if (!this.connectionsLayer || !this.nodesLayer) {
            console.log('Missing DOM layers, reinitializing...');
            this.initializeD3Canvas();
            return;
        }

        // Render connections first
        this.renderD3Connections();

        // Render nodes
        this.flatNodes.forEach(node => {
            this.createD3NodeElement(node);
        });
    }

    renderD3Connections() {
        // Create a map of nodes by ID for quick lookup
        const nodeMap = new Map();
        this.flatNodes.forEach(node => {
            nodeMap.set(node.id, node);
        });

        // Find parent-child relationships and create connections
        this.flatNodes.forEach(parentNode => {
            if (parentNode.children && parentNode.children.length > 0) {
                parentNode.children.forEach(childData => {
                    // Find the actual positioned child node
                    const childNode = nodeMap.get(childData.id);
                    if (childNode) {
                        this.createD3Connection(parentNode, childNode);
                    }
                });
            }
        });
    }

    createD3Connection(parentNode, childNode) {
        const x1 = parentNode.x + 280; // Right edge of parent
        const y1 = parentNode.y + (parentNode.type === 'Group' ? 20 : 60);   // Center of parent (adjusted for Group nodes)
        const x2 = childNode.x;         // Left edge of child
        const y2 = childNode.y + (childNode.type === 'Group' ? 20 : 60);    // Center of child (adjusted for Group nodes)

        // Create hierarchical path: horizontal from parent, then vertical, then horizontal to child
        const horizontalOffset = 30; // Distance to extend horizontally from parent
        const midX = x1 + horizontalOffset;

        // Path: horizontal out from parent, vertical down/up to child level, horizontal to child
        const pathData = `M ${x1} ${y1} L ${midX} ${y1} L ${midX} ${y2} L ${x2} ${y2}`;

        const path = document.createElementNS(SVG_NAMESPACE, 'path');
        path.setAttribute('d', pathData);
        path.setAttribute('stroke', '#0176d3');
        path.setAttribute('stroke-width', '2');
        path.setAttribute('fill', 'none');
        path.setAttribute('stroke-linecap', 'round');
        path.setAttribute('stroke-linejoin', 'round');
        path.setAttribute('opacity', '0.8');

        this.connectionsLayer.appendChild(path);
    }

    createD3NodeElement(node) {
        const nodeGroup = document.createElementNS(SVG_NAMESPACE, 'g');
        nodeGroup.setAttribute('class', 'svg-node-group');
        nodeGroup.setAttribute('data-node-id', node.id);
        nodeGroup.setAttribute('transform', `translate(${node.x}, ${node.y})`);
        nodeGroup.style.cursor = 'pointer';

        // Main card rectangle - enhanced design with more height
        const rect = document.createElementNS(SVG_NAMESPACE, 'rect');
        rect.setAttribute('x', '0');
        rect.setAttribute('y', '0');
        rect.setAttribute('width', '280');
        rect.setAttribute('height', '120');
        rect.setAttribute('rx', '8');
        rect.setAttribute('ry', '8');
        rect.setAttribute('fill', '#ffffff');
        rect.setAttribute('stroke', '#d8dde6');
        rect.setAttribute('stroke-width', '1');
        rect.setAttribute('filter', 'drop-shadow(0 2px 4px rgba(0,0,0,0.1))');

        // Header section background
        const headerRect = document.createElementNS(SVG_NAMESPACE, 'rect');
        headerRect.setAttribute('x', '0');
        headerRect.setAttribute('y', '0');
        headerRect.setAttribute('width', '280');
        headerRect.setAttribute('height', '40');
        headerRect.setAttribute('rx', '8');
        headerRect.setAttribute('ry', '8');
        headerRect.setAttribute('fill', '#f3f3f3');

        // Small icon (simplified, no background circle)
        const iconGroup = document.createElementNS(SVG_NAMESPACE, 'g');
        iconGroup.setAttribute('transform', 'translate(8, 8)');

        const iconUse = document.createElementNS(SVG_NAMESPACE, 'use');
        iconUse.setAttribute('fill', '#706e6b');
        iconUse.setAttribute('width', '16');
        iconUse.setAttribute('height', '16');

        // Map node types to SLDS icon references
        let iconReference = '';
        if (node.type === 'Account') {
            iconReference = `${sldsIcons}/utility-sprite/svg/symbols.svg#company`;
        } else if (node.type === 'Contact') {
            iconReference = `${sldsIcons}/utility-sprite/svg/symbols.svg#user`;
        } else if (node.type === 'Opportunity') {
            iconReference = `${sldsIcons}/utility-sprite/svg/symbols.svg#opportunity`;
        } else if (node.type === 'Group') {
            iconReference = `${sldsIcons}/utility-sprite/svg/symbols.svg#groups`;
        } else {
            iconReference = `${sldsIcons}/utility-sprite/svg/symbols.svg#record`;
        }

        iconUse.setAttributeNS(XLINK_NAMESPACE, XLINK_HREF, iconReference);
        iconGroup.appendChild(iconUse);

        // Title in header
        const title = document.createElementNS(SVG_NAMESPACE, 'text');
        title.setAttribute('x', '30');
        title.setAttribute('y', '18');
        title.setAttribute('fill', '#181818');
        title.setAttribute('font-size', '14');
        title.setAttribute('font-weight', '600');
        title.setAttribute('font-family', 'Salesforce Sans, Arial, sans-serif');

        // Truncate title if too long and add tooltip
        const titleText = node.title || `${node.type}_${node.id}`;
        const maxTitleLength = 28;
        const truncatedTitle = titleText.length > maxTitleLength
            ? titleText.substring(0, maxTitleLength) + '...'
            : titleText;
        title.textContent = truncatedTitle;

        // Add tooltip with full title on hover if truncated
        if (titleText.length > maxTitleLength) {
            title.appendChild(document.createElementNS(SVG_NAMESPACE, 'title')).textContent = titleText;
        }

        // Subtitle in header (lighter text)
        const subtitle = document.createElementNS(SVG_NAMESPACE, 'text');
        subtitle.setAttribute('x', '30');
        subtitle.setAttribute('y', '32');
        subtitle.setAttribute('fill', '#706e6b');
        subtitle.setAttribute('font-size', '11');
        subtitle.setAttribute('font-family', 'Salesforce Sans, Arial, sans-serif');
        subtitle.textContent = node.subtitle || 'Unknown';

        let yPosition = 60;

        // Append main elements
        if (node.type === 'Group') {
            headerRect.setAttribute('stroke', '#d8dde6');
            headerRect.setAttribute('stroke-width', '1');
            headerRect.setAttribute('filter', 'drop-shadow(0 2px 4px rgba(0,0,0,0.1))');
            nodeGroup.appendChild(headerRect);
        } else {
            nodeGroup.appendChild(rect);
            nodeGroup.appendChild(headerRect);
        }

        // Create data input fields
        if (node.details && typeof node.details === 'object') {
            // Use the new details object structure
            const fieldsToDisplay = [];
            if (node.details.field1Label && node.details.field1Value) {
                fieldsToDisplay.push({
                    label: node.details.field1Label,
                    value: node.details.field1Value
                });
            }
            if (node.details.field2Label && node.details.field2Value) {
                fieldsToDisplay.push({
                    label: node.details.field2Label,
                    value: node.details.field2Value
                });
            }

            fieldsToDisplay.forEach((field, index) => {
                if (index < 2 && yPosition < 110) { // Limit to 2 lines and within bounds
                    // Field label
                    const fieldLabel = document.createElementNS(SVG_NAMESPACE, 'text');
                    fieldLabel.setAttribute('x', '12');
                    fieldLabel.setAttribute('y', yPosition);
                    fieldLabel.setAttribute('fill', '#706e6b');
                    fieldLabel.setAttribute('font-size', '10');
                    fieldLabel.setAttribute('font-family', 'Salesforce Sans, Arial, sans-serif');
                    fieldLabel.textContent = field.label + ':';

                    // Field value (styled differently)
                    const fieldValue = document.createElementNS(SVG_NAMESPACE, 'text');
                    fieldValue.setAttribute('x', '80');
                    fieldValue.setAttribute('y', yPosition);
                    fieldValue.setAttribute('fill', '#0176d3');
                    fieldValue.setAttribute('font-size', '10');
                    fieldValue.setAttribute('font-family', 'Salesforce Sans, Arial, sans-serif');
                    fieldValue.textContent = field.value;

                    nodeGroup.appendChild(fieldLabel);
                    nodeGroup.appendChild(fieldValue);
                    yPosition += 16;
                }
            });
        }

        nodeGroup.appendChild(iconGroup);
        nodeGroup.appendChild(title);
        nodeGroup.appendChild(subtitle);

        // Expand button
        const hasChildren = node.children && node.children.length > 0;
        if (hasChildren) {
            const expandGroup = document.createElementNS(SVG_NAMESPACE, 'g');
            expandGroup.setAttribute('class', 'expand-button');
            expandGroup.setAttribute('data-node-id', node.id);
            expandGroup.style.cursor = 'pointer';

            const expandCircle = document.createElementNS(SVG_NAMESPACE, 'circle');
            expandCircle.setAttribute('cx', '280');
            expandCircle.setAttribute('cy', (node.type === 'Group' ? '20' : '60'));
            expandCircle.setAttribute('r', '8');
            expandCircle.setAttribute('fill', '#0176d3');
            expandCircle.setAttribute('stroke', '#ffffff');
            expandCircle.setAttribute('stroke-width', '1');

            // Create chevron/arrow icon instead of text
            const isExpanded = node.isExpanded !== false; // Default to expanded
            const chevron = document.createElementNS(SVG_NAMESPACE, 'path');

            const centerY = node.type === 'Group' ? '20' : '60';
            const verticalStart = node.type === 'Group' ? '15' : '55';
            const verticalEnd = node.type === 'Group' ? '25' : '65';

            if (isExpanded) {
                // Minus sign for expanded state
                chevron.setAttribute('d', `M275 ${centerY} L285 ${centerY}`);
            } else {
                // Plus sign for collapsed state  
                chevron.setAttribute('d', `M275 ${centerY} L285 ${centerY} M280 ${verticalStart} L280 ${verticalEnd}`);
            }

            chevron.setAttribute('stroke', '#ffffff');
            chevron.setAttribute('stroke-width', '1.5');
            chevron.setAttribute('fill', '#ffffff');
            chevron.setAttribute('stroke-linecap', 'round');
            chevron.setAttribute('stroke-linejoin', 'round');

            expandGroup.appendChild(expandCircle);
            expandGroup.appendChild(chevron);

            // Add click handler for expansion
            expandGroup.addEventListener('click', (e) => {
                e.stopPropagation();
                this.handleToggleExpandD3(node.id);
            });

            nodeGroup.appendChild(expandGroup);
        }

        // Navigation icon for child nodes
        if (node.type !== 'Group' && node.id) {
            const navGroup = document.createElementNS(SVG_NAMESPACE, 'g');
            navGroup.setAttribute('class', 'nav-button');
            navGroup.setAttribute('data-node-id', node.id);
            navGroup.style.cursor = 'pointer';

            // SLDS external link icon
            const navIcon = document.createElementNS(SVG_NAMESPACE, 'g');
            navIcon.setAttribute('transform', 'translate(252, 12)');

            const iconUse = document.createElementNS(SVG_NAMESPACE, 'use');
            iconUse.setAttribute('width', '12');
            iconUse.setAttribute('height', '12');
            iconUse.setAttribute('fill', '#706e6b');
            iconUse.setAttributeNS(XLINK_NAMESPACE, XLINK_HREF, `${sldsIcons}/utility-sprite/svg/symbols.svg#new_window`);

            navIcon.appendChild(iconUse);
            navGroup.appendChild(navIcon);

            // Add click handler for navigation
            navGroup.addEventListener('click', (e) => {
                e.stopPropagation();
                this.handleNavigateToRecord(node.id, node.type);
            });

            nodeGroup.appendChild(navGroup);
        }

        // Add click handler for node selection
        nodeGroup.addEventListener('click', (e) => {
            if (!e.target.closest('.expand-button') && !e.target.closest('.nav-button')) {
                this.handleNodeClick(node.id);
            }
        });

        this.nodesLayer.appendChild(nodeGroup);
    }

    handleToggleExpandD3(nodeId) {
        const toggleNodeExpansion = (nodes) => {
            return nodes.map(node => {
                if (node.id === nodeId) {
                    return { ...node, isExpanded: !node.isExpanded };
                } else if (node.children && node.children.length > 0) {
                    return { ...node, children: toggleNodeExpansion(node.children) };
                }
                return node;
            });
        };

        if (this.treeData && this.treeData.length > 0) {
            this.treeData = toggleNodeExpansion(this.treeData);
            // Re-render with updated data
            setTimeout(() => {
                this.renderD3Hierarchy();
            }, 50);
        }
    }

    // Pan and drag event handlers Start
    handleCanvasMouseDown(event) {
        // Only start dragging if clicking on the SVG background, not on nodes
        if (event.target === this.svgElement || event.target === this.mainGroup) {
            this.isDragging = true;
            this.lastMouseX = event.clientX;
            this.lastMouseY = event.clientY;
            event.preventDefault();
        }
    }

    handleCanvasMouseMove(event) {
        if (this.isDragging) {
            const deltaX = event.clientX - this.lastMouseX;
            const deltaY = event.clientY - this.lastMouseY;

            this.panX += deltaX;
            this.panY += deltaY;

            this.lastMouseX = event.clientX;
            this.lastMouseY = event.clientY;

            // Update the transform
            this.renderD3Hierarchy();
            event.preventDefault();
        }
    }

    handleCanvasMouseUp() {
        this.isDragging = false;
    }

    handleCanvasMouseLeave() {
        this.isDragging = false;
    }

    handleCanvasWheel(event) {
        event.preventDefault();

        // Get mouse position relative to the SVG
        const rect = this.svgElement.getBoundingClientRect();
        const mouseX = event.clientX - rect.left;
        const mouseY = event.clientY - rect.top;

        // Calculate zoom factor
        const zoomFactor = event.deltaY > 0 ? 0.9 : 1.1;
        const newZoomLevel = this.zoomLevel * zoomFactor;

        // Clamp zoom level to min/max bounds
        if (newZoomLevel >= this.minZoom && newZoomLevel <= this.maxZoom) {
            // Calculate the point in world coordinates before zoom
            const worldX = (mouseX - this.panX) / this.zoomLevel;
            const worldY = (mouseY - this.panY) / this.zoomLevel;

            // Update zoom level
            this.zoomLevel = newZoomLevel;

            // Adjust pan to keep the mouse position fixed
            this.panX = mouseX - worldX * this.zoomLevel;
            this.panY = mouseY - worldY * this.zoomLevel;

            this.updateZoomLevelText();
            this.renderD3Hierarchy();
        }
    }

    // Pan and drag event handlers End

    // Zoom control handlers Start
    handleZoomIn() {
        if (this.zoomLevel < this.maxZoom) {
            this.zoomLevel = Math.min(this.maxZoom, this.zoomLevel * 1.2);
            this.updateZoomLevelText();
            this.renderD3Hierarchy();
        }
    }

    handleZoomOut() {
        if (this.zoomLevel > this.minZoom) {
            this.zoomLevel = Math.max(this.minZoom, this.zoomLevel / 1.2);
            this.updateZoomLevelText();
            this.renderD3Hierarchy();
        }
    }

    handleZoomReset() {
        this.zoomLevel = 1.0;
        this.panX = 50;
        this.panY = 50;
        this.updateZoomLevelText();
    }

    findNodeById(nodeId, nodes) {
        for (let node of nodes) {
            if (node.id === nodeId) return node;
            if (node.children && node.children.length > 0) {
                const found = this.findNodeById(nodeId, node.children);
                if (found) return found;
            }
        }
        return null;
    }

    handleNavigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }
}