// macOS: Use mouseup for selection detection
document.addEventListener('mouseup', function(e) {
    // Ignore selections within margin notes
    if (e.target.closest('.crux-margin-note') || e.target.closest('.crux-margin')) {
        return;
    }
    
    // Ignore right-clicks - we handle those separately
    if (e.button === 2) {
        return;
    }
    
    const cfiData = CruxCFI.getSelectionCFI();
    if (cfiData && cfiData.text.length > 0) {
        window.webkit.messageHandlers.textSelection.postMessage(cfiData);
        // Clear the browser's native selection after capturing it
        // This prevents the native selection from visually interfering with our highlight spans
        window.getSelection().removeAllRanges();
    }
});

// Handle right-click context menu
document.addEventListener('contextmenu', function(e) {
    // Ignore selections within margin notes
    if (e.target.closest('.crux-margin-note') || e.target.closest('.crux-margin')) {
        return;
    }
    
    const selection = window.getSelection();
    const selectedText = selection.toString().trim();
    
    if (selectedText.length > 0) {
        // Prevent default browser context menu
        e.preventDefault();
        
        // Get CFI data for the selection
        const cfiData = CruxCFI.getSelectionCFI();
        if (cfiData) {
            // Send context menu request to Swift
            window.webkit.messageHandlers.contextMenuRequest.postMessage({
                text: cfiData.text,
                context: cfiData.context,
                startPath: cfiData.startPath,
                startOffset: cfiData.startOffset,
                endPath: cfiData.endPath,
                endOffset: cfiData.endOffset,
                images: cfiData.images || [],
                x: e.clientX,
                y: e.clientY
            });
        }
    }
});
