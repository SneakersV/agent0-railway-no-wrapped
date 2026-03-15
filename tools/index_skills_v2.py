import os

def index_skills():
    skills_dir = "/a0/usr/skills"
    output_path = "/per/memory/skills_index.md"
    
    if not os.path.exists(skills_dir):
        with open(output_path, "w") as f:
            f.write("# Specialized AI Skills Index\nNo custom skills found.")
        return

    skills = [d for d in os.listdir(skills_dir) if os.path.isdir(os.path.join(skills_dir, d))]
    
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("# Specialized AI Skills Index\n")
        f.write("Use these direct instructions to call custom skills without researching them.\n\n")
        
        for skill in skills:
            skill_path = os.path.join(skills_dir, skill)
            skill_md = os.path.join(skill_path, "SKILL.md")
            
            f.write(f"## Skill: {skill}\n")
            f.write(f"- **Path**: `{skill_path}`\n")
            
            if os.path.exists(skill_md):
                try:
                    with open(skill_md, "r", encoding="utf-8") as sm:
                        content = sm.read()
                        # Extract first paragraph or small section
                        f.write("### Instructions:\n")
                        f.write(content[:1000] + ("..." if len(content) > 1000 else ""))
                        f.write("\n\n")
                except:
                    f.write("- *Error reading SKILL.md*\n\n")
            else:
                # Fallback: list files
                files = os.listdir(skill_path)
                f.write(f"- **Files**: {', '.join(files)}\n\n")

if __name__ == "__main__":
    index_skills()
