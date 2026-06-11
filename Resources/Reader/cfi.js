/**
 * CruxCFI — EPUB Canonical Fragment Identifier utilities.
 *
 * "CFI" here is a simplified, Crux-internal variant of the EPUB CFI
 * standard. We only need enough to round-trip text selections between
 * the WebView (where the user picks them) and Swift storage (where they
 * are persisted as `Highlight.cfiRange`).
 *
 * Format:
 *   - **Element path:** `/4/2/1` — 1-based child indices starting from
 *     `document.body`, skipping whitespace-only text nodes so the path
 *     is stable across pretty-printing or insignificant DOM noise.
 *   - **Combined range:** `<startPath>:<startOffset>,<endPath>:<endOffset>`
 *     — used by selections that span text nodes.
 *
 * `getSelectionCFI()` is the canonical writer. The reader counterparts
 * live in `highlighter.js` (`findNodeByPath`, `scrollToCFI`).
 *
 * Message contract (posted to Swift via
 * `webkit.messageHandlers.textSelection`):
 *   {
 *     text:        string,   // the selected substring
 *     startPath:   string,   // element path to the start text node
 *     startOffset: number,
 *     endPath:     string,
 *     endOffset:   number,
 *     context:     string    // ±500 chars of surrounding text
 *   }
 */
const CruxCFI = {
    getPathToNode: function(node) {
        const path = [];
        let current = node;
        while (current && current !== document.body && current.parentNode) {
            const parent = current.parentNode;
            const children = Array.from(parent.childNodes).filter(c =>
                c.nodeType !== Node.TEXT_NODE || c.textContent.trim() !== ''
            );
            let position = 0;
            for (let i = 0; i < children.length; i++) {
                position++;
                if (children[i] === current) break;
            }
            path.unshift(position);
            current = parent;
        }
        return '/' + path.join('/');
    },

    getSelectionCFI: function() {
        const selection = window.getSelection();
        if (!selection || selection.isCollapsed || selection.rangeCount === 0) return null;

        const range = selection.getRangeAt(0);
        const text = selection.toString().trim();
        if (!text) return null;

        let startNode = range.startContainer;
        let endNode = range.endContainer;

        if (startNode.nodeType !== Node.TEXT_NODE) {
            startNode = this.getFirstTextNode(startNode);
        }
        if (endNode.nodeType !== Node.TEXT_NODE) {
            endNode = this.getLastTextNode(endNode);
        }
        if (!startNode || !endNode) return null;

        const context = this.getSurroundingContext(range, 500);

        return {
            startPath: this.getPathToNode(startNode),
            startOffset: range.startOffset,
            endPath: this.getPathToNode(endNode),
            endOffset: range.endOffset,
            text: text,
            context: context,
            images: this.getNearbyImages(range)
        };
    },

    /// Collect images near a selection so vision-capable models can "see"
    /// the figure a passage refers to. We look inside the selection's
    /// nearest block ancestor and a couple of element siblings on either
    /// side (figures usually sit just above/below the prose that discusses
    /// them). Returns up to `maxImages` source strings — already inline
    /// `data:` URIs in most EPUBs (see EPUBParser image inlining), or
    /// absolute URLs otherwise. Oversized payloads are skipped to keep
    /// requests within provider limits.
    getNearbyImages: function(range) {
        const maxImages = 4;
        const maxDataURILength = 6 * 1024 * 1024; // ~4.5 MB decoded ceiling
        const blockTags = new Set(['P','DIV','SECTION','ARTICLE','FIGURE','LI','TD','BLOCKQUOTE','MAIN','BODY']);

        let block = range.commonAncestorContainer;
        if (block.nodeType === Node.TEXT_NODE) block = block.parentElement;
        while (block && block !== document.body && !blockTags.has(block.tagName)) {
            block = block.parentElement;
        }
        if (!block) return [];

        // Candidate containers: the block itself plus 2 siblings each side.
        const containers = [block];
        let prev = block.previousElementSibling, next = block.nextElementSibling, hops = 0;
        while ((prev || next) && hops < 2) {
            if (prev) { containers.push(prev); prev = prev.previousElementSibling; }
            if (next) { containers.push(next); next = next.nextElementSibling; }
            hops++;
        }

        const seen = new Set();
        const out = [];
        for (const container of containers) {
            if (out.length >= maxImages) break;
            const imgs = container.matches && container.matches('img, image')
                ? [container]
                : Array.from(container.querySelectorAll('img, image'));
            for (const el of imgs) {
                if (out.length >= maxImages) break;
                const src = el.getAttribute('src')
                    || el.getAttribute('href')
                    || el.getAttribute('xlink:href')
                    || (el.currentSrc || '');
                if (!src) continue;
                const ok = src.startsWith('data:image/') || src.startsWith('http://') || src.startsWith('https://');
                if (!ok) continue;
                if (src.length > maxDataURILength) continue;
                if (seen.has(src)) continue;
                seen.add(src);
                out.push(src);
            }
        }
        return out;
    },

    getFirstTextNode: function(node) {
        if (node.nodeType === Node.TEXT_NODE) return node;
        for (const child of node.childNodes) {
            const result = this.getFirstTextNode(child);
            if (result) return result;
        }
        return null;
    },

    getLastTextNode: function(node) {
        if (node.nodeType === Node.TEXT_NODE) return node;
        for (let i = node.childNodes.length - 1; i >= 0; i--) {
            const result = this.getLastTextNode(node.childNodes[i]);
            if (result) return result;
        }
        return null;
    },

    getSurroundingContext: function(range, contextLength) {
        const body = document.body;
        const fullText = body.textContent || '';
        const preRange = document.createRange();
        preRange.setStart(body, 0);
        preRange.setEnd(range.startContainer, range.startOffset);
        const startPos = preRange.toString().length;
        const endPos = startPos + range.toString().length;
        const contextStart = Math.max(0, startPos - contextLength);
        const contextEnd = Math.min(fullText.length, endPos + contextLength);
        return fullText.substring(contextStart, contextEnd);
    }
};
