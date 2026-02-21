import sys

def analyze_brackets(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    stack = []
    
    # We only care about lines inside the build method properly, but let's just parse the whole file.
    # We need to handle strings and comments to be accurate.
    
    in_multiline_comment = False
    
    errors = []

    for line_idx, line in enumerate(lines):
        i = 0
        while i < len(line):
            char = line[i]
            
            # Skip comments
            if not in_multiline_comment:
                if line[i:i+2] == '//':
                    break # End of line comment
                elif line[i:i+2] == '/*':
                    in_multiline_comment = True
                    i += 2
                    continue
            else:
                if line[i:i+2] == '*/':
                    in_multiline_comment = False
                    i += 2
                    continue
                i += 1
                continue
                
            # Skip Strings (simplified, doesn't handle interpolation braces strictly but usually fine)
            if char in ('"', "'"):
                quote = char
                i += 1
                while i < len(line):
                    if line[i] == quote and (i == 0 or line[i-1] != '\\'):
                        break
                    i += 1
                if i >= len(line):
                     pass # String continues to next line (Dart multiline strings), but let's ignore for simple checker
                i += 1
                continue

            if char in '({[':
                stack.append((char, line_idx + 1, i + 1))
            elif char in ')}]':
                if not stack:
                    errors.append(f"Unexpected closing {char} at line {line_idx+1}:{i+1}")
                else:
                    last_open, last_line, last_col = stack.pop()
                    expected = {'(': ')', '{': '}', '[': ']'}[last_open]
                    if char != expected:
                        errors.append(f"Mismatch: Expected {expected} for {last_open}({last_line}:{last_col}) but found {char} at {line_idx+1}:{i+1}")
            
            i += 1

    if stack:
        for open_char, line_num, col in stack:
            errors.append(f"Unclosed {open_char} at {line_num}:{col}")

    if errors:
        print("Errors found:")
        for e in errors:
            print(e)
    else:
        print("No errors found.")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python count_brackets.py <filename>")
    else:
        analyze_brackets(sys.argv[1])
