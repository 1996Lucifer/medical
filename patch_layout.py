import os

filepath = "/Users/dj/Projects/medical_agent/flutter_source/lib/settings/camera_settings_detail_screen.dart"
with open(filepath, "r") as f:
    content = f.read()

body_start = content.find("            child: Column(\n              children: [\n                // Live Stream Feed")
body_end = content.find("                  ),\n                ),\n              ],\n            ),\n          ),\n        ),\n      ),")

if body_start == -1 or body_end == -1:
    print("Could not find boundaries!")
    exit(1)

feed_start = content.find("                Flexible(\n                  flex: 5,\n                  child: GlassCard(")
feed_end = content.find("                const SizedBox(height: 16),\n                // Tabs")
tabs_start = content.find("                // Tabs")
tabs_end = content.find("                  ),\n                ),\n              ],")

feed_code = content[feed_start:feed_end].strip()
# Adjust indentation for feed code (it's currently at 16 spaces)
tabs_code = content[tabs_start:tabs_end].strip()

# Create the new layout builder
new_layout = """            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildFeedCard(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _buildTabsArea(),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      Flexible(
                        flex: 5,
                        child: _buildFeedCard(),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 5,
                        child: _buildTabsArea(),
                      ),
                    ],
                  );
                }
              },
            ),"""

# Create the methods to inject
methods = f"""
  Widget _buildFeedCard() {{
    return {feed_code.replace('Flexible(', 'Container(').replace('flex: 5,', '')};
  }}

  Widget _buildTabsArea() {{
    return Column(
      children: [
{tabs_code.replace('                ', '        ')}
      ],
    );
  }}
"""

# Wait, `feed_code` starts with `Flexible`. We just replace the outer Flexible with Container, but it's easier to just return the GlassCard.
feed_code_glasscard = feed_code.replace("Flexible(\n                  flex: 5,\n                  child: GlassCard(", "GlassCard(")
# Remove the last `)` from Flexible
feed_code_glasscard = feed_code_glasscard[:-1]

methods = f"""
  Widget _buildFeedCard() {{
    return {feed_code_glasscard};
  }}

  Widget _buildTabsArea() {{
    return Column(
      children: [
{tabs_code.replace('                ', '        ')}
      ],
    );
  }}
"""

new_content = content[:body_start] + new_layout + content[tabs_end + len("                  ),\n                ),\n              ],"):]

# Inject methods before _buildROITab()
roi_tab_start = new_content.find("  Widget _buildROITab() {")
new_content = new_content[:roi_tab_start] + methods + "\n" + new_content[roi_tab_start:]

with open(filepath, "w") as f:
    f.write(new_content)
print("Updated successfully")
