const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "react/no-unknown-property";

pub const Options = struct {
    ignore: core.ReactNoUnknownPropertyIgnoreNames = .{},
    require_data_lowercase: bool = false,
};

const NameMap = struct {
    from: []const u8,
    to: []const u8,
};

const TagsMap = struct {
    name: []const u8,
    tags: []const []const u8,
};

const NameText = struct {
    value: []const u8,
    owned: bool = false,

    fn deinit(self: NameText, allocator: Allocator) void {
        if (self.owned) allocator.free(self.value);
    }
};

const dom_attribute_names = [_]NameMap{
    .{ .from = "accept-charset", .to = "acceptCharset" },
    .{ .from = "class", .to = "className" },
    .{ .from = "http-equiv", .to = "httpEquiv" },
    .{ .from = "crossorigin", .to = "crossOrigin" },
    .{ .from = "for", .to = "htmlFor" },
    .{ .from = "nomodule", .to = "noModule" },
};

const attribute_tags_map = [_]TagsMap{
    .{ .name = "abbr", .tags = &[_][]const u8{ "th", "td" } },
    .{ .name = "charset", .tags = &[_][]const u8{"meta"} },
    .{ .name = "checked", .tags = &[_][]const u8{"input"} },
    .{ .name = "crossOrigin", .tags = &[_][]const u8{ "script", "img", "video", "audio", "link", "image" } },
    .{ .name = "displaystyle", .tags = &[_][]const u8{"math"} },
    .{ .name = "download", .tags = &[_][]const u8{ "a", "area" } },
    .{ .name = "fill", .tags = &[_][]const u8{ "altGlyph", "circle", "ellipse", "g", "line", "marker", "mask", "path", "polygon", "polyline", "rect", "svg", "symbol", "text", "textPath", "tref", "tspan", "use", "animate", "animateColor", "animateMotion", "animateTransform", "set" } },
    .{ .name = "focusable", .tags = &[_][]const u8{"svg"} },
    .{ .name = "imageSizes", .tags = &[_][]const u8{"link"} },
    .{ .name = "imageSrcSet", .tags = &[_][]const u8{"link"} },
    .{ .name = "property", .tags = &[_][]const u8{"meta"} },
    .{ .name = "viewBox", .tags = &[_][]const u8{ "marker", "pattern", "svg", "symbol", "view" } },
    .{ .name = "as", .tags = &[_][]const u8{"link"} },
    .{ .name = "align", .tags = &[_][]const u8{ "applet", "caption", "col", "colgroup", "hr", "iframe", "img", "table", "tbody", "td", "tfoot", "th", "thead", "tr" } },
    .{ .name = "valign", .tags = &[_][]const u8{ "tr", "td", "th", "thead", "tbody", "tfoot", "colgroup", "col" } },
    .{ .name = "noModule", .tags = &[_][]const u8{"script"} },
    .{ .name = "onAbort", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onCancel", .tags = &[_][]const u8{"dialog"} },
    .{ .name = "onCanPlay", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onCanPlayThrough", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onClose", .tags = &[_][]const u8{"dialog"} },
    .{ .name = "onDurationChange", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onEmptied", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onEncrypted", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onEnded", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onError", .tags = &[_][]const u8{ "audio", "video", "img", "link", "source", "script", "picture", "iframe" } },
    .{ .name = "onLoad", .tags = &[_][]const u8{ "script", "img", "link", "picture", "iframe", "object", "source" } },
    .{ .name = "onLoadedData", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onLoadedMetadata", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onLoadStart", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onPause", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onPlay", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onPlaying", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onProgress", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onRateChange", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onResize", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onSeeked", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onSeeking", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onStalled", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onSuspend", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onTimeUpdate", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onVolumeChange", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "onWaiting", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "autoPictureInPicture", .tags = &[_][]const u8{"video"} },
    .{ .name = "controls", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "controlsList", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "disablePictureInPicture", .tags = &[_][]const u8{"video"} },
    .{ .name = "disableRemotePlayback", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "loop", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "muted", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "playsInline", .tags = &[_][]const u8{"video"} },
    .{ .name = "allowFullScreen", .tags = &[_][]const u8{ "iframe", "video" } },
    .{ .name = "webkitAllowFullScreen", .tags = &[_][]const u8{ "iframe", "video" } },
    .{ .name = "mozAllowFullScreen", .tags = &[_][]const u8{ "iframe", "video" } },
    .{ .name = "poster", .tags = &[_][]const u8{"video"} },
    .{ .name = "preload", .tags = &[_][]const u8{ "audio", "video" } },
    .{ .name = "scrolling", .tags = &[_][]const u8{"iframe"} },
    .{ .name = "returnValue", .tags = &[_][]const u8{"dialog"} },
    .{ .name = "webkitDirectory", .tags = &[_][]const u8{"input"} },
    .{ .name = "shadowrootmode", .tags = &[_][]const u8{"template"} },
    .{ .name = "shadowrootclonable", .tags = &[_][]const u8{"template"} },
    .{ .name = "shadowrootdelegatesfocus", .tags = &[_][]const u8{"template"} },
    .{ .name = "shadowrootserializable", .tags = &[_][]const u8{"template"} },
    .{ .name = "transform-origin", .tags = &[_][]const u8{"rect"} },
};

const svg_dom_attribute_names = [_]NameMap{
    .{ .from = "accent-height", .to = "accentHeight" },
    .{ .from = "alignment-baseline", .to = "alignmentBaseline" },
    .{ .from = "arabic-form", .to = "arabicForm" },
    .{ .from = "baseline-shift", .to = "baselineShift" },
    .{ .from = "cap-height", .to = "capHeight" },
    .{ .from = "clip-path", .to = "clipPath" },
    .{ .from = "clip-rule", .to = "clipRule" },
    .{ .from = "color-interpolation", .to = "colorInterpolation" },
    .{ .from = "color-interpolation-filters", .to = "colorInterpolationFilters" },
    .{ .from = "color-profile", .to = "colorProfile" },
    .{ .from = "color-rendering", .to = "colorRendering" },
    .{ .from = "dominant-baseline", .to = "dominantBaseline" },
    .{ .from = "enable-background", .to = "enableBackground" },
    .{ .from = "fill-opacity", .to = "fillOpacity" },
    .{ .from = "fill-rule", .to = "fillRule" },
    .{ .from = "flood-color", .to = "floodColor" },
    .{ .from = "flood-opacity", .to = "floodOpacity" },
    .{ .from = "font-family", .to = "fontFamily" },
    .{ .from = "font-size", .to = "fontSize" },
    .{ .from = "font-size-adjust", .to = "fontSizeAdjust" },
    .{ .from = "font-stretch", .to = "fontStretch" },
    .{ .from = "font-style", .to = "fontStyle" },
    .{ .from = "font-variant", .to = "fontVariant" },
    .{ .from = "font-weight", .to = "fontWeight" },
    .{ .from = "glyph-name", .to = "glyphName" },
    .{ .from = "glyph-orientation-horizontal", .to = "glyphOrientationHorizontal" },
    .{ .from = "glyph-orientation-vertical", .to = "glyphOrientationVertical" },
    .{ .from = "horiz-adv-x", .to = "horizAdvX" },
    .{ .from = "horiz-origin-x", .to = "horizOriginX" },
    .{ .from = "image-rendering", .to = "imageRendering" },
    .{ .from = "letter-spacing", .to = "letterSpacing" },
    .{ .from = "lighting-color", .to = "lightingColor" },
    .{ .from = "marker-end", .to = "markerEnd" },
    .{ .from = "marker-mid", .to = "markerMid" },
    .{ .from = "marker-start", .to = "markerStart" },
    .{ .from = "overline-position", .to = "overlinePosition" },
    .{ .from = "overline-thickness", .to = "overlineThickness" },
    .{ .from = "paint-order", .to = "paintOrder" },
    .{ .from = "panose-1", .to = "panose1" },
    .{ .from = "pointer-events", .to = "pointerEvents" },
    .{ .from = "rendering-intent", .to = "renderingIntent" },
    .{ .from = "shape-rendering", .to = "shapeRendering" },
    .{ .from = "stop-color", .to = "stopColor" },
    .{ .from = "stop-opacity", .to = "stopOpacity" },
    .{ .from = "strikethrough-position", .to = "strikethroughPosition" },
    .{ .from = "strikethrough-thickness", .to = "strikethroughThickness" },
    .{ .from = "stroke-dasharray", .to = "strokeDasharray" },
    .{ .from = "stroke-dashoffset", .to = "strokeDashoffset" },
    .{ .from = "stroke-linecap", .to = "strokeLinecap" },
    .{ .from = "stroke-linejoin", .to = "strokeLinejoin" },
    .{ .from = "stroke-miterlimit", .to = "strokeMiterlimit" },
    .{ .from = "stroke-opacity", .to = "strokeOpacity" },
    .{ .from = "stroke-width", .to = "strokeWidth" },
    .{ .from = "text-anchor", .to = "textAnchor" },
    .{ .from = "text-decoration", .to = "textDecoration" },
    .{ .from = "text-rendering", .to = "textRendering" },
    .{ .from = "underline-position", .to = "underlinePosition" },
    .{ .from = "underline-thickness", .to = "underlineThickness" },
    .{ .from = "unicode-bidi", .to = "unicodeBidi" },
    .{ .from = "unicode-range", .to = "unicodeRange" },
    .{ .from = "units-per-em", .to = "unitsPerEm" },
    .{ .from = "v-alphabetic", .to = "vAlphabetic" },
    .{ .from = "v-hanging", .to = "vHanging" },
    .{ .from = "v-ideographic", .to = "vIdeographic" },
    .{ .from = "v-mathematical", .to = "vMathematical" },
    .{ .from = "vector-effect", .to = "vectorEffect" },
    .{ .from = "vert-adv-y", .to = "vertAdvY" },
    .{ .from = "vert-origin-x", .to = "vertOriginX" },
    .{ .from = "vert-origin-y", .to = "vertOriginY" },
    .{ .from = "word-spacing", .to = "wordSpacing" },
    .{ .from = "writing-mode", .to = "writingMode" },
    .{ .from = "x-height", .to = "xHeight" },
    .{ .from = "xlink:actuate", .to = "xlinkActuate" },
    .{ .from = "xlink:arcrole", .to = "xlinkArcrole" },
    .{ .from = "xlink:href", .to = "xlinkHref" },
    .{ .from = "xlink:role", .to = "xlinkRole" },
    .{ .from = "xlink:show", .to = "xlinkShow" },
    .{ .from = "xlink:title", .to = "xlinkTitle" },
    .{ .from = "xlink:type", .to = "xlinkType" },
    .{ .from = "xml:base", .to = "xmlBase" },
    .{ .from = "xml:lang", .to = "xmlLang" },
    .{ .from = "xml:space", .to = "xmlSpace" },
};

const dom_property_names_one_word = [_][]const u8{
    "dir",      "draggable", "hidden",     "id",        "lang",        "nonce",     "part",       "slot",      "style",         "title",               "translate",   "inert",
    "accept",   "action",    "allow",      "alt",       "as",          "async",     "buffered",   "capture",   "challenge",     "cite",                "code",        "cols",
    "content",  "coords",    "csp",        "data",      "decoding",    "default",   "defer",      "disabled",  "form",          "headers",             "height",      "high",
    "href",     "icon",      "importance", "integrity", "kind",        "label",     "language",   "loading",   "list",          "loop",                "low",         "manifest",
    "max",      "media",     "method",     "min",       "multiple",    "muted",     "name",       "open",      "optimum",       "pattern",             "ping",        "placeholder",
    "poster",   "preload",   "profile",    "rel",       "required",    "reversed",  "role",       "rows",      "sandbox",       "scope",               "seamless",    "selected",
    "shape",    "size",      "sizes",      "span",      "src",         "start",     "step",       "summary",   "target",        "type",                "value",       "width",
    "wmode",    "wrap",      "accumulate", "additive",  "alphabetic",  "amplitude", "ascent",     "azimuth",   "bbox",          "begin",               "bias",        "by",
    "clip",     "color",     "cursor",     "cx",        "cy",          "d",         "decelerate", "descent",   "direction",     "display",             "divisor",     "dur",
    "dx",       "dy",        "elevation",  "end",       "exponent",    "fill",      "filter",     "format",    "from",          "fr",                  "fx",          "fy",
    "g1",       "g2",        "hanging",    "hreflang",  "ideographic", "in",        "in2",        "intercept", "k",             "k1",                  "k2",          "k3",
    "k4",       "kerning",   "local",      "mask",      "mode",        "offset",    "opacity",    "operator",  "order",         "orient",              "orientation", "origin",
    "overflow", "path",      "points",     "r",         "radius",      "restart",   "result",     "rotate",    "rx",            "ry",                  "scale",       "seed",
    "slope",    "spacing",   "speed",      "stemh",     "stemv",       "string",    "stroke",     "to",        "transform",     "u1",                  "u2",          "unicode",
    "values",   "version",   "visibility", "widths",    "x",           "x1",        "x2",         "xmlns",     "y",             "y1",                  "y2",          "z",
    "property", "ref",       "key",        "children",  "results",     "security",  "controls",   "popover",   "popovertarget", "popovertargetaction",
};

const dom_property_names_two_words = [_][]const u8{
    "accessKey",                  "autoCapitalize",          "autoFocus",                      "contentEditable",          "enterKeyHint",           "exportParts",             "inputMode",               "itemID",
    "itemRef",                    "itemProp",                "itemScope",                      "itemType",                 "spellCheck",             "tabIndex",                "acceptCharset",           "autoComplete",
    "autoPlay",                   "border",                  "cellPadding",                    "cellSpacing",              "classID",                "codeBase",                "colSpan",                 "contextMenu",
    "dateTime",                   "encType",                 "formAction",                     "formEncType",              "formMethod",             "formNoValidate",          "formTarget",              "frameBorder",
    "hrefLang",                   "httpEquiv",               "imageSizes",                     "imageSrcSet",              "isMap",                  "keyParams",               "keyType",                 "marginHeight",
    "marginWidth",                "maxLength",               "mediaGroup",                     "minLength",                "noValidate",             "onAnimationEnd",          "onAnimationIteration",    "onAnimationStart",
    "onBlur",                     "onChange",                "onClick",                        "onContextMenu",            "onCopy",                 "onCompositionEnd",        "onCompositionStart",      "onCompositionUpdate",
    "onCut",                      "onDoubleClick",           "onDrag",                         "onDragEnd",                "onDragEnter",            "onDragExit",              "onDragLeave",             "onError",
    "onFocus",                    "onInput",                 "onKeyDown",                      "onKeyPress",               "onKeyUp",                "onLoad",                  "onWheel",                 "onDragOver",
    "onDragStart",                "onDrop",                  "onMouseDown",                    "onMouseEnter",             "onMouseLeave",           "onMouseMove",             "onMouseOut",              "onMouseOver",
    "onMouseUp",                  "onPaste",                 "onScroll",                       "onSelect",                 "onSubmit",               "onBeforeToggle",          "onToggle",                "onTransitionEnd",
    "radioGroup",                 "readOnly",                "referrerPolicy",                 "rowSpan",                  "srcDoc",                 "srcLang",                 "srcSet",                  "useMap",
    "fetchPriority",              "crossOrigin",             "accentHeight",                   "alignmentBaseline",        "arabicForm",             "attributeName",           "attributeType",           "baseFrequency",
    "baselineShift",              "baseProfile",             "calcMode",                       "capHeight",                "clipPathUnits",          "clipPath",                "clipRule",                "colorInterpolation",
    "colorInterpolationFilters",  "colorProfile",            "colorRendering",                 "contentScriptType",        "contentStyleType",       "diffuseConstant",         "dominantBaseline",        "edgeMode",
    "enableBackground",           "fillOpacity",             "fillRule",                       "filterRes",                "filterUnits",            "floodColor",              "floodOpacity",            "fontFamily",
    "fontSize",                   "fontSizeAdjust",          "fontStretch",                    "fontStyle",                "fontVariant",            "fontWeight",              "glyphName",               "glyphOrientationHorizontal",
    "glyphOrientationVertical",   "glyphRef",                "gradientTransform",              "gradientUnits",            "horizAdvX",              "horizOriginX",            "imageRendering",          "kernelMatrix",
    "kernelUnitLength",           "keyPoints",               "keySplines",                     "keyTimes",                 "lengthAdjust",           "letterSpacing",           "lightingColor",           "limitingConeAngle",
    "markerEnd",                  "markerMid",               "markerStart",                    "markerHeight",             "markerUnits",            "markerWidth",             "maskContentUnits",        "maskUnits",
    "mathematical",               "numOctaves",              "overlinePosition",               "overlineThickness",        "panose1",                "paintOrder",              "pathLength",              "patternContentUnits",
    "patternTransform",           "patternUnits",            "pointerEvents",                  "pointsAtX",                "pointsAtY",              "pointsAtZ",               "preserveAlpha",           "preserveAspectRatio",
    "primitiveUnits",             "refX",                    "refY",                           "rendering-intent",         "repeatCount",            "repeatDur",               "requiredExtensions",      "requiredFeatures",
    "shapeRendering",             "specularConstant",        "specularExponent",               "spreadMethod",             "startOffset",            "stdDeviation",            "stitchTiles",             "stopColor",
    "stopOpacity",                "strikethroughPosition",   "strikethroughThickness",         "strokeDasharray",          "strokeDashoffset",       "strokeLinecap",           "strokeLinejoin",          "strokeMiterlimit",
    "strokeOpacity",              "strokeWidth",             "surfaceScale",                   "systemLanguage",           "tableValues",            "targetX",                 "targetY",                 "textAnchor",
    "textDecoration",             "textRendering",           "textLength",                     "transformOrigin",          "underlinePosition",      "underlineThickness",      "unicodeBidi",             "unicodeRange",
    "unitsPerEm",                 "vAlphabetic",             "vHanging",                       "vIdeographic",             "vMathematical",          "vectorEffect",            "vertAdvY",                "vertOriginX",
    "vertOriginY",                "viewBox",                 "viewTarget",                     "wordSpacing",              "writingMode",            "xHeight",                 "xChannelSelector",        "xlinkActuate",
    "xlinkArcrole",               "xlinkHref",               "xlinkRole",                      "xlinkShow",                "xlinkTitle",             "xlinkType",               "xmlBase",                 "xmlLang",
    "xmlnsXlink",                 "xmlSpace",                "yChannelSelector",               "zoomAndPan",               "autoCorrect",            "autoSave",                "className",               "dangerouslySetInnerHTML",
    "defaultValue",               "defaultChecked",          "htmlFor",                        "onBeforeInput",            "onInvalid",              "onReset",                 "onTouchCancel",           "onTouchEnd",
    "onTouchMove",                "onTouchStart",            "suppressContentEditableWarning", "suppressHydrationWarning", "onAbort",                "onCanPlay",               "onCanPlayThrough",        "onDurationChange",
    "onEmptied",                  "onEncrypted",             "onEnded",                        "onLoadedData",             "onLoadedMetadata",       "onLoadStart",             "onPause",                 "onPlay",
    "onPlaying",                  "onProgress",              "onRateChange",                   "onResize",                 "onSeeked",               "onSeeking",               "onStalled",               "onSuspend",
    "onTimeUpdate",               "onVolumeChange",          "onWaiting",                      "onCopyCapture",            "onCutCapture",           "onPasteCapture",          "onCompositionEndCapture", "onCompositionStartCapture",
    "onCompositionUpdateCapture", "onFocusCapture",          "onBlurCapture",                  "onChangeCapture",          "onBeforeInputCapture",   "onInputCapture",          "onResetCapture",          "onSubmitCapture",
    "onInvalidCapture",           "onLoadCapture",           "onErrorCapture",                 "onKeyDownCapture",         "onKeyPressCapture",      "onKeyUpCapture",          "onAbortCapture",          "onCanPlayCapture",
    "onCanPlayThroughCapture",    "onDurationChangeCapture", "onEmptiedCapture",               "onEncryptedCapture",       "onEndedCapture",         "onLoadedDataCapture",     "onLoadedMetadataCapture", "onLoadStartCapture",
    "onPauseCapture",             "onPlayCapture",           "onPlayingCapture",               "onProgressCapture",        "onRateChangeCapture",    "onSeekedCapture",         "onSeekingCapture",        "onStalledCapture",
    "onSuspendCapture",           "onTimeUpdateCapture",     "onVolumeChangeCapture",          "onWaitingCapture",         "onSelectCapture",        "onTouchCancelCapture",    "onTouchEndCapture",       "onTouchMoveCapture",
    "onTouchStartCapture",        "onScrollCapture",         "onWheelCapture",                 "onAnimationEndCapture",    "onAnimationIteration",   "onAnimationStartCapture", "onTransitionEndCapture",  "onAuxClick",
    "onAuxClickCapture",          "onClickCapture",          "onContextMenuCapture",           "onDoubleClickCapture",     "onDragCapture",          "onDragEndCapture",        "onDragEnterCapture",      "onDragExitCapture",
    "onDragLeaveCapture",         "onDragOverCapture",       "onDragStartCapture",             "onDropCapture",            "onMouseDownCapture",     "onMouseMoveCapture",      "onMouseOutCapture",       "onMouseOverCapture",
    "onMouseUpCapture",           "autoPictureInPicture",    "controlsList",                   "disablePictureInPicture",  "disableRemotePlayback",  "popoverTarget",           "popoverTargetAction",     "onGotPointerCapture",
    "onGotPointerCaptureCapture", "onLostPointerCapture",    "onLostPointerCaptureCapture",    "onPointerCancel",          "onPointerCancelCapture", "onPointerDown",           "onPointerDownCapture",    "onPointerEnter",
    "onPointerEnterCapture",      "onPointerLeave",          "onPointerLeaveCapture",          "onPointerMove",            "onPointerMoveCapture",   "onPointerOut",            "onPointerOutCapture",     "onPointerOver",
    "onPointerOverCapture",       "onPointerUp",             "onPointerUpCapture",             "precedence",
};

const dom_properties_ignore_case = [_][]const u8{
    "charset",
    "allowFullScreen",
    "webkitAllowFullScreen",
    "mozAllowFullScreen",
    "webkitDirectory",
    "popoverTarget",
    "popoverTargetAction",
};

const aria_properties = [_][]const u8{
    "aria-atomic",           "aria-braillelabel", "aria-brailleroledescription", "aria-busy",         "aria-controls",   "aria-current",
    "aria-describedby",      "aria-description",  "aria-details",                "aria-disabled",     "aria-dropeffect", "aria-errormessage",
    "aria-flowto",           "aria-grabbed",      "aria-haspopup",               "aria-hidden",       "aria-invalid",    "aria-keyshortcuts",
    "aria-label",            "aria-labelledby",   "aria-live",                   "aria-owns",         "aria-relevant",   "aria-roledescription",
    "aria-autocomplete",     "aria-checked",      "aria-expanded",               "aria-level",        "aria-modal",      "aria-multiline",
    "aria-multiselectable",  "aria-orientation",  "aria-placeholder",            "aria-pressed",      "aria-readonly",   "aria-required",
    "aria-selected",         "aria-sort",         "aria-valuemax",               "aria-valuemin",     "aria-valuenow",   "aria-valuetext",
    "aria-activedescendant", "aria-colcount",     "aria-colindex",               "aria-colindextext", "aria-colspan",    "aria-posinset",
    "aria-rowcount",         "aria-rowindex",     "aria-rowindextext",           "aria-rowspan",      "aria-setsize",
};

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    attribute: ast.JSXAttribute,
    index: ast.NodeIndex,
    parent_index: ?ast.NodeIndex,
    options: Options,
) Allocator.Error!void {
    const actual_name_text = try jsxNameText(allocator, tree, attribute.name) orelse return;
    defer actual_name_text.deinit(allocator);

    if (tagNameHasDot(tree, parent_index)) return;

    const actual_name = actual_name_text.value;
    if (options.ignore.contains(actual_name)) return;

    const name = normalizeAttributeCase(actual_name);

    if (isValidDataAttribute(name)) {
        if (!options.require_data_lowercase or isLowercaseDataAttributeName(name)) return;
    }
    if (isValidAriaAttribute(name)) return;

    const opening = jsxOpeningElement(tree, parent_index) orelse return;
    const tag_name = jsxIdentifierName(tree, opening.name) orelse return;

    if (std.mem.eql(u8, tag_name, "fbt") or std.mem.eql(u8, tag_name, "fbs")) return;
    if (!isValidHTMLTagInJSX(tree, opening, tag_name)) return;

    if (allowedTagsFor(name)) |allowed_tags| {
        if (!contains(allowed_tags, tag_name)) {
            const allowed = try std.mem.join(allocator, ", ", allowed_tags);
            defer allocator.free(allowed);
            try core.addDiagnosticFmt(
                allocator,
                diagnostics,
                .@"error",
                id,
                tree.span(index),
                "Invalid property '{s}' found on tag '{s}', but it is only allowed on: {s}",
                .{ actual_name, tag_name, allowed },
            );
        }
        return;
    }

    const standard_name = getStandardName(name);
    if (standard_name) |standard| {
        if (std.mem.eql(u8, standard, name)) return;
        const message = try std.fmt.allocPrint(allocator, "Unknown property '{s}' found, use '{s}' instead", .{ actual_name, standard });
        defer allocator.free(message);
        const fix = core.Fix{ .span = tree.span(attribute.name), .replacement = standard };
        const name_span = tree.span(attribute.name);
        const can_fix = std.mem.eql(u8, tree.source[name_span.start..name_span.end], actual_name) and
            try canRenameAttribute(allocator, tree, opening, index, tag_name, standard);
        try core.addDiagnosticWithFixes(allocator, diagnostics, .@"error", id, message, tree.span(index), if (can_fix) &.{fix} else &.{});
        return;
    }

    try core.addDiagnosticFmt(
        allocator,
        diagnostics,
        .@"error",
        id,
        tree.span(index),
        "Unknown property '{s}' found",
        .{actual_name},
    );
}

// Refuse collisions with both existing properties and other aliases that could
// be renamed in the same fix pass.
fn canRenameAttribute(allocator: Allocator, tree: *const ast.Tree, opening: ast.JSXOpeningElement, index: ast.NodeIndex, tag_name: []const u8, replacement: []const u8) Allocator.Error!bool {
    if (allowedTagsFor(replacement)) |tags| if (!contains(tags, tag_name)) return false;
    for (tree.extra(opening.attributes)) |other_index| {
        if (other_index == index) continue;
        const other = switch (tree.data(other_index)) {
            .jsx_attribute => |value| value,
            else => continue,
        };
        const text = try jsxNameText(allocator, tree, other.name) orelse continue;
        defer text.deinit(allocator);
        const normalized = normalizeAttributeCase(text.value);
        const target = getStandardName(normalized) orelse normalized;
        if (std.mem.eql(u8, target, replacement)) return false;
    }
    return true;
}

fn jsxOpeningElement(tree: *const ast.Tree, parent_index: ?ast.NodeIndex) ?ast.JSXOpeningElement {
    const index = parent_index orelse return null;
    return switch (tree.data(index)) {
        .jsx_opening_element => |opening| opening,
        else => null,
    };
}

fn tagNameHasDot(tree: *const ast.Tree, parent_index: ?ast.NodeIndex) bool {
    const opening = jsxOpeningElement(tree, parent_index) orelse return false;
    return switch (tree.data(opening.name)) {
        .jsx_member_expression => true,
        else => false,
    };
}

fn isValidHTMLTagInJSX(tree: *const ast.Tree, opening: ast.JSXOpeningElement, tag_name: []const u8) bool {
    if (!isLowercaseTagName(tag_name)) return false;

    for (tree.extra(opening.attributes)) |attribute_index| {
        const attribute = switch (tree.data(attribute_index)) {
            .jsx_attribute => |attribute| attribute,
            else => continue,
        };
        const name = jsxIdentifierName(tree, attribute.name) orelse continue;
        if (std.mem.eql(u8, name, "is")) return false;
    }

    return true;
}

fn isLowercaseTagName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isLower(name[0])) return false;
    return std.mem.indexOfScalar(u8, name, '-') == null;
}

fn normalizeAttributeCase(name: []const u8) []const u8 {
    for (&dom_properties_ignore_case) |property| {
        if (std.ascii.eqlIgnoreCase(property, name)) return property;
    }
    return name;
}

fn isValidDataAttribute(name: []const u8) bool {
    if (startsWithIgnoreCase(name, "data-xml")) return false;
    return std.mem.startsWith(u8, name, "data-") and std.mem.indexOfScalar(u8, name, ':') == null;
}

fn isLowercaseDataAttributeName(name: []const u8) bool {
    for (name["data-".len..]) |byte| {
        if (std.ascii.isUpper(byte)) return false;
    }
    return true;
}

fn isValidAriaAttribute(name: []const u8) bool {
    return contains(&aria_properties, name);
}

fn allowedTagsFor(name: []const u8) ?[]const []const u8 {
    for (&attribute_tags_map) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry.tags;
    }
    return null;
}

fn getStandardName(name: []const u8) ?[]const u8 {
    if (lookupMap(&dom_attribute_names, name)) |standard| return standard;
    if (lookupMap(&svg_dom_attribute_names, name)) |standard| return standard;
    if (findCaseInsensitive(&dom_property_names_two_words, name)) |standard| return standard;
    if (findCaseInsensitive(&dom_property_names_one_word, name)) |standard| return standard;
    return null;
}

fn lookupMap(entries: []const NameMap, name: []const u8) ?[]const u8 {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.from, name)) return entry.to;
    }
    return null;
}

fn findCaseInsensitive(values: []const []const u8, name: []const u8) ?[]const u8 {
    for (values) |value| {
        if (std.ascii.eqlIgnoreCase(value, name)) return value;
    }
    return null;
}

fn contains(values: []const []const u8, expected: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, expected)) return true;
    }
    return false;
}

fn startsWithIgnoreCase(value: []const u8, prefix: []const u8) bool {
    if (value.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(value[0..prefix.len], prefix);
}

fn jsxNameText(allocator: Allocator, tree: *const ast.Tree, index: ast.NodeIndex) Allocator.Error!?NameText {
    return switch (tree.data(index)) {
        .jsx_identifier => |identifier| .{ .value = tree.string(identifier.name) },
        .jsx_namespaced_name => |name| blk: {
            const namespace = jsxIdentifierName(tree, name.namespace) orelse return null;
            const local = jsxIdentifierName(tree, name.name) orelse return null;
            break :blk .{ .value = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ namespace, local }), .owned = true };
        },
        else => null,
    };
}

fn jsxIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(index)) {
        .jsx_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}
